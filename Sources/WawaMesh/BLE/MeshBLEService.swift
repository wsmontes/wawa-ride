import Foundation
@preconcurrency import CoreBluetooth
// CoreBluetoothMock → real CoreBluetooth aliases (must be public for delegate conformance)
public typealias CBMCentralManager = CBCentralManager
public typealias CBMCentralManagerDelegate = CBCentralManagerDelegate
public typealias CBMPeripheralManager = CBPeripheralManager
public typealias CBMPeripheralManagerDelegate = CBPeripheralManagerDelegate
public typealias CBMPeripheralDelegate = CBPeripheralDelegate
public typealias CBMCentral = CBCentral
public typealias CBMPeripheral = CBPeripheral
public typealias CBMService = CBService
public typealias CBMCharacteristic = CBCharacteristic
public typealias CBMATTRequest = CBATTRequest
// import BitFoundation — flat target: types compiled in same module
import os.log

/// Dual-role BLE mesh service (Central + Peripheral simultaneously).
///
/// Built on BitChat's BinaryProtocol v2 wire format. BitChat provides the
/// encode/decode, fragment format, and dedup key pattern. WawaRide provides
/// the application-layer payloads (CompactLocation, AnnouncePayload, etc.).
///
/// Key patterns from BitChat:
/// 1. Simultaneous Central (scanner) + Peripheral (advertiser)
/// 2. GATT write-based messaging (not MultipeerConnectivity) — works in background
/// 3. Flood relay: receive → dedup → decrement TTL → re-broadcast to all except ingress
/// 4. Fragment assembly for payloads > MTU (469 bytes)
///
/// CoreBluetoothMock:
/// Using `import CoreBluetoothMock` instead of `import CoreBluetooth` allows
/// this code to run on the iOS Simulator. On real devices, it forwards to native CB.
public final class MeshBLEService: NSObject, ObservableObject, @unchecked Sendable {

    // MARK: - BLE protocol constants (from BitChat TransportConfig)

    private static let fragmentSize = 469       // bleDefaultFragmentSize
    private static let maxCentralLinks = 6       // bleMaxCentralLinks
    private static let maxInFlightAssemblies = 128  // bleMaxInFlightAssemblies
    private static let defaultTTL: UInt8 = 5      // Wawa-tuned (BitChat uses 7)
    private static let dedupMaxAge: TimeInterval = 300  // messageDedupMaxAgeSeconds
    private static let dedupMaxCount = 1000       // messageDedupMaxCount

    @Published public var connectedPeerCount = 0

    private let serviceUUID = CBUUID(string: "A1B2C3D4-5E6F-7A8B-9C0D-E1F2A3B4C5D6")
    private let charUUID    = CBUUID(string: "B2C3D4E5-6F7A-8B9C-0D1E-F2A3B4C5D6E7")

    private var centralManager: CBMCentralManager!
    private var peripheralManager: CBMPeripheralManager!
    private var txCharacteristic: CBMutableCharacteristic?
    private var connectedPeripherals: [UUID: CBMPeripheral] = [:]
    private var subscribedCentrals: [CBMCentral] = []
    private let fragmentAssembly = FragmentAssemblyBuffer()
    private let deduplicator = MessageDeduplicator()
    private let log = Logger(subsystem: "com.wawaride.mesh", category: "BLE")

    /// 8-byte persistent peer identity (survives app restarts).
    public var localPeerID: Data = {
        let key = "wawa_mesh_peer_id"
        if let saved = UserDefaults.standard.data(forKey: key), saved.count == 8 { return saved }
        var id = Data(count: 8)
        _ = id.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 8, $0.baseAddress!) }
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    public var onPacketReceived: ((BitchatPacket) -> Void)?
    public var onPeerCountChanged: ((Int) -> Void)?

    public override init() {
        super.init()
        centralManager = CBMCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionRestoreIdentifierKey: "com.wawaride.central"
        ])
        peripheralManager = CBMPeripheralManager(delegate: self, queue: nil)
    }

    public func start() {
        if centralManager.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: [serviceUUID], options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: false
            ])
        }
    }

    public func stop() {
        centralManager.stopScan()
        peripheralManager.stopAdvertising()
        connectedPeripherals.values.forEach { centralManager.cancelPeripheralConnection($0) }
        connectedPeripherals.removeAll()
        subscribedCentrals.removeAll()
        updatePeerCount()
    }

    /// Broadcast packet to all connected peers via GATT write.
    /// Encodes via BitChat's BinaryProtocol (via BitchatPacket.toBinaryData), fragments if needed.
    public func broadcast(_ packet: BitchatPacket) {
        var p = packet
        p.ttl = adaptiveTTL()
        guard let encoded = p.toBinaryData() else { return }
        if encoded.count <= Self.fragmentSize {
            sendToAll(encoded)
        } else {
            for chunk in FragmentCodec.fragment(encoded, maxSize: Self.fragmentSize) {
                sendToAll(chunk)
            }
        }
    }

    private func adaptiveTTL() -> UInt8 {
        switch connectedPeerCount {
        case 0...3:  return 5
        case 4...6:  return 3
        default:     return 2
        }
    }

    // MARK: - Internal

    private func sendToAll(_ data: Data, excluding: UUID? = nil) {
        for (id, peripheral) in connectedPeripherals where id != excluding {
            if let svc = peripheral.services?.first(where: { $0.uuid == serviceUUID }),
               let ch = svc.characteristics?.first(where: { $0.uuid == charUUID }) {
                peripheral.writeValue(data, for: ch, type: .withResponse)
            }
        }
        if let tx = txCharacteristic, !subscribedCentrals.isEmpty {
            peripheralManager.updateValue(data, for: tx, onSubscribedCentrals: subscribedCentrals)
        }
    }

    /// Receive pipeline: fragment assembly → decode → dedup → relay → deliver.
    /// Reference: BitChat's BLEReceivePipeline.swift
    private func handleIncoming(_ data: Data, from peerUUID: UUID) {
        // Step 1: Fragment reassembly
        if FragmentCodec.isFragment(data) {
            guard let assembled = fragmentAssembly.addFragment(data, from: peerUUID) else { return }
            handleIncoming(assembled, from: peerUUID)
            return
        }
        // Step 2: Decode via BitChat's BitchatPacket.from (BinaryProtocol)
        guard let packet = BitchatPacket.from(data) else { return }
        // Step 3: Dedup (matching BitChat's key format)
        let dedupKey = "\(packet.senderID.hex)-\(packet.timestamp)-\(packet.type)"
        guard deduplicator.isNew(dedupKey) else { return }
        // Step 4: Relay if TTL > 1
        if packet.ttl > 1 {
            var relayed = packet
            relayed.ttl = packet.ttl - 1
            if let encoded = relayed.toBinaryData() {
                sendToAll(encoded, excluding: peerUUID)
            }
        }
        // Step 5: Deliver
        onPacketReceived?(packet)
    }

    private func updatePeerCount() {
        let count = connectedPeripherals.count + subscribedCentrals.count
        DispatchQueue.main.async {
            self.connectedPeerCount = count
            self.onPeerCountChanged?(count)
        }
    }
}

// MARK: - CBMCentralManagerDelegate
extension MeshBLEService: CBMCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBMCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: [serviceUUID], options: nil)
        }
    }

    public func centralManager(_ central: CBMCentralManager, willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBMPeripheral] {
            for peripheral in peripherals {
                connectedPeripherals[peripheral.identifier] = peripheral
                peripheral.delegate = self
            }
            updatePeerCount()
        }
    }

    public func centralManager(_ central: CBMCentralManager, didDiscover peripheral: CBMPeripheral,
                                advertisementData: [String: Any], rssi: NSNumber) {
        guard connectedPeripherals[peripheral.identifier] == nil,
              connectedPeripherals.count < Self.maxCentralLinks else { return }
        connectedPeripherals[peripheral.identifier] = peripheral
        central.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBMCentralManager, didConnect peripheral: CBMPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
        updatePeerCount()
    }

    public func centralManager(_ central: CBMCentralManager, didDisconnectPeripheral peripheral: CBMPeripheral, error: Error?) {
        connectedPeripherals.removeValue(forKey: peripheral.identifier)
        updatePeerCount()
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: [serviceUUID], options: nil)
        }
    }
}

// MARK: - CBMPeripheralDelegate
extension MeshBLEService: CBMPeripheralDelegate {
    public func peripheral(_ peripheral: CBMPeripheral, didDiscoverServices error: Error?) {
        guard let svc = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else { return }
        peripheral.discoverCharacteristics([charUUID], for: svc)
    }

    public func peripheral(_ peripheral: CBMPeripheral, didDiscoverCharacteristicsFor service: CBMService, error: Error?) {
        guard let ch = service.characteristics?.first(where: { $0.uuid == charUUID }) else { return }
        peripheral.setNotifyValue(true, for: ch)
    }

    public func peripheral(_ peripheral: CBMPeripheral, didUpdateValueFor characteristic: CBMCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        handleIncoming(data, from: peripheral.identifier)
    }
}

// MARK: - CBMPeripheralManagerDelegate
extension MeshBLEService: CBMPeripheralManagerDelegate {
    public func peripheralManagerDidUpdateState(_ peripheral: CBMPeripheralManager) {
        guard peripheral.state == .poweredOn else { return }
        let ch = CBMutableCharacteristic(type: charUUID, properties: [.read, .write, .notify],
                                         value: nil, permissions: [.readable, .writeable])
        let svc = CBMutableService(type: serviceUUID, primary: true)
        svc.characteristics = [ch]
        txCharacteristic = ch
        peripheralManager.add(svc)
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataLocalNameKey: "WawaRide"
        ])
    }

    public func peripheralManager(_ peripheral: CBMPeripheralManager, central: CBMCentral,
                                   didSubscribeTo characteristic: CBMCharacteristic) {
        subscribedCentrals.append(central)
        updatePeerCount()
    }

    public func peripheralManager(_ peripheral: CBMPeripheralManager, central: CBMCentral,
                                   didUnsubscribeFrom characteristic: CBMCharacteristic) {
        subscribedCentrals.removeAll { $0.identifier == central.identifier }
        updatePeerCount()
    }

    public func peripheralManager(_ peripheral: CBMPeripheralManager, didReceiveWrite requests: [CBMATTRequest]) {
        for req in requests {
            if let data = req.value {
                handleIncoming(data, from: req.central.identifier)
            }
            peripheral.respond(to: req, withResult: .success)
        }
    }
}
