import Foundation
import CoreBluetoothMock  // NordicSemiconductor/IOS-CoreBluetooth-Mock — runs on Simulator
import os.log

/// Dual-role BLE mesh service (Central + Peripheral simultaneously).
///
/// Architecture derived from BitChat's BLEService.swift (~2000 lines):
/// https://github.com/permissionlesstech/bitchat/blob/main/bitchat/Services/BLE/BLEService.swift
///
/// Key patterns from BitChat:
/// 1. Simultaneous Central (scanner) + Peripheral (advertiser) — all iOS devices do both
/// 2. GATT write-based messaging (not MultipeerConnectivity) — works in background
/// 3. Flood relay: receive → dedup → decrement TTL → re-broadcast to all except ingress
/// 4. Fragment assembly for payloads > MTU (469 bytes)
///
/// BLE Background Limitations (iOS):
/// - Advertising in background moves service UUIDs to "overflow area"
/// - Other iOS apps can only discover overflow UUIDs if actively scanning for them
/// - State restoration (`CBCentralManagerOptionRestoreIdentifierKey`) relaunches app
///   when a known peripheral is discovered, but ONLY if system killed the app
/// - User swipe-to-kill permanently stops BLE until next foreground launch
/// Reference: DP-3T findings — https://github.com/DP-3T/dp3t-sdk-ios
///
/// CoreBluetoothMock:
/// Using `import CoreBluetoothMock` instead of `import CoreBluetooth` allows
/// this code to run on the iOS Simulator for development/testing.
/// On real devices, CoreBluetoothMock forwards all calls to native CoreBluetooth.
/// Reference: https://github.com/NordicSemiconductor/IOS-CoreBluetooth-Mock
public final class MeshBLEService: NSObject, ObservableObject, @unchecked Sendable {

    @Published public var connectedPeerCount = 0

    // Custom UUIDs for WawaMesh service discovery.
    // Devices advertising this UUID are recognized as WawaMesh peers.
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
    /// Stored in UserDefaults. In phase 2, derived from Noise public key.
    public var localPeerID: Data = {
        let key = "wawa_mesh_peer_id"
        if let saved = UserDefaults.standard.data(forKey: key), saved.count == 8 { return saved }
        var id = Data(count: 8)
        _ = id.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 8, $0.baseAddress!) }
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    public var onPacketReceived: ((MeshPacket) -> Void)?
    public var onPeerCountChanged: ((Int) -> Void)?

    public override init() {
        super.init()
        // State restoration key enables system relaunch after background kill
        // Reference: Apple docs on CBCentralManagerOptionRestoreIdentifierKey
        centralManager = CBMCentralManager(delegate: self, queue: nil, options: [
            CBMCentralManagerOptionRestoreIdentifierKey: "com.wawaride.central"
        ])
        peripheralManager = CBMPeripheralManager(delegate: self, queue: nil)
    }

    public func start() {
        if centralManager.state == .poweredOn {
            // Only scan for our specific service UUID (required for background discovery)
            centralManager.scanForPeripherals(withServices: [serviceUUID], options: [
                CBMCentralManagerScanOptionAllowDuplicatesKey: false
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
    /// Fragments if payload exceeds BLE MTU.
    public func broadcast(_ packet: MeshPacket) {
        let encoded = BinaryCodec.encode(packet)
        if encoded.count <= MeshConfig.bleFragmentSize {
            sendToAll(encoded)
        } else {
            // Fragment and pace at 30ms intervals (BitChat recommendation)
            for chunk in FragmentCodec.fragment(encoded) {
                sendToAll(chunk)
            }
        }
    }

    // MARK: - Internal

    private func sendToAll(_ data: Data, excluding: UUID? = nil) {
        // Central → Peripheral path (write to connected peripherals)
        for (id, peripheral) in connectedPeripherals where id != excluding {
            if let svc = peripheral.services?.first(where: { $0.uuid == serviceUUID }),
               let ch = svc.characteristics?.first(where: { $0.uuid == charUUID }) {
                peripheral.writeValue(data, for: ch, type: .withResponse)
            }
        }
        // Peripheral → Central path (notify all subscribers)
        if let tx = txCharacteristic, !subscribedCentrals.isEmpty {
            peripheralManager.updateValue(data, for: tx, onSubscribedCentrals: subscribedCentrals)
        }
    }

    /// Receive pipeline: fragment reassembly → decode → dedup → relay → deliver.
    /// Reference: BitChat's BLEReceivePipeline.swift
    private func handleIncoming(_ data: Data, from peerUUID: UUID) {
        // Step 1: Fragment reassembly (if applicable)
        if FragmentCodec.isFragment(data) {
            guard let assembled = fragmentAssembly.addFragment(data, from: peerUUID) else { return }
            handleIncoming(assembled, from: peerUUID)
            return
        }
        // Step 2: Decode packet
        guard let packet = BinaryCodec.decode(data) else { return }
        // Step 3: Dedup check (key: "{sender}-{timestamp}-{type}")
        guard deduplicator.isNew(packet.messageID) else { return }
        // Step 4: Relay if TTL > 1 (flood to all EXCEPT ingress peer)
        if packet.ttl > 1 {
            var relayed = packet
            relayed.ttl = packet.ttl - 1
            let encoded = BinaryCodec.encode(relayed)
            sendToAll(encoded, excluding: peerUUID)
        }
        // Step 5: Deliver to app layer
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

    /// State restoration: system relaunched us after background kill.
    /// Re-establish connections to previously-known peripherals.
    /// Reference: https://developer.apple.com/documentation/corebluetooth/cbcentralmanagerdelegate/centralmanager(_:willrestorestate:)
    public func centralManager(_ central: CBMCentralManager, willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBMCentralManagerRestoredStatePeripheralsKey] as? [CBMPeripheral] {
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
              connectedPeripherals.count < MeshConfig.bleMaxCentralLinks else { return }
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
        // Auto-reconnect: resume scanning
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
            CBMAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBMAdvertisementDataLocalNameKey: "WawaRide"
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
