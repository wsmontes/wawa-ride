import Foundation
import CoreBluetoothMock
import os.log

/// Dual-role BLE mesh service (Central + Peripheral simultaneously).
/// Adapted from BitChat's BLEService architecture.
public final class MeshBLEService: NSObject, ObservableObject, @unchecked Sendable {

    @Published public var connectedPeerCount = 0

    private let serviceUUID = CBUUID(string: "A1B2C3D4-5E6F-7A8B-9C0D-E1F2A3B4C5D6")
    private let charUUID    = CBUUID(string: "B2C3D4E5-6F7A-8B9C-0D1E-F2A3B4C5D6E7")

    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!
    private var txCharacteristic: CBMutableCharacteristic?
    private var connectedPeripherals: [UUID: CBPeripheral] = [:]
    private var subscribedCentrals: [CBCentral] = []
    private let fragmentAssembly = FragmentAssemblyBuffer()
    private let deduplicator = MessageDeduplicator()
    private let log = Logger(subsystem: "com.wawaride.mesh", category: "BLE")

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
        centralManager = CBCentralManager(delegate: self, queue: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
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

    /// Broadcast packet to all connected peers. Fragments if > MTU.
    public func broadcast(_ packet: MeshPacket) {
        let encoded = BinaryCodec.encode(packet)
        if encoded.count <= MeshConfig.bleFragmentSize {
            sendToAll(encoded)
        } else {
            for chunk in FragmentCodec.fragment(encoded) {
                sendToAll(chunk)
            }
        }
    }

    // MARK: - Private

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

    private func handleIncoming(_ data: Data, from peerUUID: UUID) {
        if FragmentCodec.isFragment(data) {
            guard let assembled = fragmentAssembly.addFragment(data, from: peerUUID) else { return }
            handleIncoming(assembled, from: peerUUID)
            return
        }
        guard let packet = BinaryCodec.decode(data) else { return }
        guard deduplicator.isNew(packet.messageID) else { return }
        // Relay if TTL > 1
        if packet.ttl > 1 {
            var relayed = packet
            relayed.ttl = packet.ttl - 1
            let encoded = BinaryCodec.encode(relayed)
            sendToAll(encoded, excluding: peerUUID)
        }
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

// MARK: - CBCentralManagerDelegate
extension MeshBLEService: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: [serviceUUID], options: nil)
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                advertisementData: [String: Any], rssi: NSNumber) {
        guard connectedPeripherals[peripheral.identifier] == nil,
              connectedPeripherals.count < MeshConfig.bleMaxCentralLinks else { return }
        connectedPeripherals[peripheral.identifier] = peripheral
        central.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
        updatePeerCount()
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripherals.removeValue(forKey: peripheral.identifier)
        updatePeerCount()
        // Reconnect scan
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: [serviceUUID], options: nil)
        }
    }
}

// MARK: - CBPeripheralDelegate
extension MeshBLEService: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else { return }
        peripheral.discoverCharacteristics([charUUID], for: svc)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let ch = service.characteristics?.first(where: { $0.uuid == charUUID }) else { return }
        peripheral.setNotifyValue(true, for: ch)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        handleIncoming(data, from: peripheral.identifier)
    }
}

// MARK: - CBPeripheralManagerDelegate
extension MeshBLEService: CBPeripheralManagerDelegate {
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
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

    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                                   didSubscribeTo characteristic: CBCharacteristic) {
        subscribedCentrals.append(central)
        updatePeerCount()
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                                   didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribedCentrals.removeAll { $0.identifier == central.identifier }
        updatePeerCount()
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for req in requests {
            if let data = req.value {
                handleIncoming(data, from: req.central.identifier)
            }
            peripheral.respond(to: req, withResult: .success)
        }
    }
}
