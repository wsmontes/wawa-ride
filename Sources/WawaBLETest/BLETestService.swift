import Foundation
@preconcurrency import CoreBluetooth

/// Minimal BLE mesh test — two iPhones discover, connect, and exchange messages.
///
/// BLE delegates fire on arbitrary queues. We bridge to @MainActor for UI safety.
@MainActor
final class BLETestService: NSObject, ObservableObject, @unchecked Sendable {
    @Published var connectedPeerCount = 0
    @Published var isRunning = false
    @Published var log: [String] = []

    private let serviceUUID = CBUUID(string: "A1B2C3D4-5E6F-7A8B-9C0D-E1F2A3B4C5D6")
    private let charUUID    = CBUUID(string: "B2C3D4E5-6F7A-8B9C-0D1E-F2A3B4C5D6E7")

    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!
    private var txCharacteristic: CBMutableCharacteristic?
    private var connectedPeripherals: [UUID: CBPeripheral] = [:]
    private var subscribedCentrals: [CBCentral] = []

    /// persistent 8-byte peer identity.
    let localPeerID: Data = {
        let key = "wawa_mesh_peer_id"
        if let saved = UserDefaults.standard.data(forKey: key), saved.count == 8 { return saved }
        var id = Data(count: 8)
        _ = id.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 8, $0.baseAddress!) }
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    var localPeerIDHex: String {
        localPeerID.map { String(format: "%02x", $0) }.joined()
    }

    private func addLog(_ msg: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        log.append("[\(ts)] \(msg)")
        if log.count > 200 { log.removeFirst(100) }
    }

    // MARK: - Lifecycle

    func start() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        isRunning = true
        addLog("BLE initializing...")
    }

    func stop() {
        centralManager.stopScan()
        peripheralManager.stopAdvertising()
        connectedPeripherals.values.forEach { centralManager.cancelPeripheralConnection($0) }
        connectedPeripherals.removeAll()
        subscribedCentrals.removeAll()
        isRunning = false
        connectedPeerCount = 0
        addLog("BLE stopped")
    }

    // MARK: - Send

    func broadcastTest(_ message: String) {
        guard let payload = message.data(using: .utf8) else { return }
        sendToAll(payload)
        addLog("SENT: \(message)")
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

    private func handleIncoming(_ data: Data, from peerUUID: UUID) {
        if let text = String(data: data, encoding: .utf8) {
            let short = peerUUID.uuidString.prefix(8)
            addLog("RECV [\(short)]: \(text)")
        } else {
            addLog("RECV [\(peerUUID.uuidString.prefix(8))]: \(data.count)B binary")
        }

        // Relay: re-broadcast to all other peers (simple flood, no TTL)
        sendToAll(data, excluding: peerUUID)
    }

    private func updatePeerCount() {
        connectedPeerCount = connectedPeripherals.count + subscribedCentrals.count
    }
}

// MARK: - CBCentralManagerDelegate
// BLE delegates fire on internal BLE queues. We use @unchecked Sendable + @MainActor
// to satisfy Swift 6 while keeping UI updates on main.
extension BLETestService: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state == .poweredOn {
                central.scanForPeripherals(withServices: [serviceUUID], options: [
                    CBCentralManagerScanOptionAllowDuplicatesKey: false
                ])
                addLog("Scanning for peers...")
            } else {
                addLog("Central state: \(central.state.rawValue)")
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                     didDiscover peripheral: CBPeripheral,
                                     advertisementData: [String: Any], rssi: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "?"
        let rssiVal = rssi.intValue
        Task { @MainActor in
            guard connectedPeripherals[peripheral.identifier] == nil,
                  connectedPeripherals.count < 6 else { return }
            connectedPeripherals[peripheral.identifier] = peripheral
            addLog("Discovered: \(name) RSSI=\(rssiVal)")
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                     didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            peripheral.delegate = self
            peripheral.discoverServices([serviceUUID])
            addLog("Connected: \(peripheral.name ?? "?")")
            updatePeerCount()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                     didDisconnectPeripheral peripheral: CBPeripheral,
                                     error: Error?) {
        Task { @MainActor in
            connectedPeripherals.removeValue(forKey: peripheral.identifier)
            addLog("Disconnected: \(peripheral.name ?? "?")")
            updatePeerCount()
            if central.state == .poweredOn {
                central.scanForPeripherals(withServices: [serviceUUID], options: nil)
            }
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BLETestService: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let svc = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else { return }
            peripheral.discoverCharacteristics([charUUID], for: svc)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didDiscoverCharacteristicsFor service: CBService,
                                 error: Error?) {
        Task { @MainActor in
            guard let ch = service.characteristics?.first(where: { $0.uuid == charUUID }) else { return }
            peripheral.setNotifyValue(true, for: ch)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didUpdateValueFor characteristic: CBCharacteristic,
                                 error: Error?) {
        Task { @MainActor in
            guard let data = characteristic.value else { return }
            handleIncoming(data, from: peripheral.identifier)
        }
    }
}

// MARK: - CBPeripheralManagerDelegate
extension BLETestService: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        Task { @MainActor in
            guard peripheral.state == .poweredOn else {
                addLog("Peripheral state: \(peripheral.state.rawValue)")
                return
            }
            let ch = CBMutableCharacteristic(
                type: charUUID,
                properties: [.read, .write, .notify],
                value: nil,
                permissions: [.readable, .writeable]
            )
            let svc = CBMutableService(type: serviceUUID, primary: true)
            svc.characteristics = [ch]
            txCharacteristic = ch
            peripheralManager.add(svc)
            let name = "Wawa-\(localPeerIDHex.prefix(4))"
            peripheralManager.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
                CBAdvertisementDataLocalNameKey: name
            ])
            addLog("Advertising as \(name)")
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager,
                                        central: CBCentral,
                                        didSubscribeTo characteristic: CBCharacteristic) {
        Task { @MainActor in
            subscribedCentrals.append(central)
            addLog("Subscriber: \(central.identifier.uuidString.prefix(8))")
            updatePeerCount()
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager,
                                        central: CBCentral,
                                        didUnsubscribeFrom characteristic: CBCharacteristic) {
        Task { @MainActor in
            subscribedCentrals.removeAll { $0.identifier == central.identifier }
            updatePeerCount()
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager,
                                        didReceiveWrite requests: [CBATTRequest]) {
        let items: [(Data?, UUID)] = requests.map { ($0.value, $0.central.identifier) }
        for req in requests { peripheral.respond(to: req, withResult: .success) }
        Task { @MainActor in
            for (data, centralID) in items {
                if let data { handleIncoming(data, from: centralID) }
            }
        }
    }
}
