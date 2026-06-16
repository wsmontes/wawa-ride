import Foundation
@preconcurrency import CoreBluetooth

/// BLE mesh service using BitChat BinaryProtocol v2 wire format.
///
/// Full BitChat stack: BitchatPacket → toBinaryData() → BLE GATT → from() → BitchatPacket
/// Includes TTL-based flood relay, dedup, fragment reassembly, and compression.
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
    private let fragmentAssembly = FragmentAssemblyBuffer()
    private let deduplicator = MessageDeduplicator()

    /// Persistent 8-byte peer identity.
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
        addLog("BLE mesh starting (BitChat BinaryProtocol v2)...")
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

    // MARK: - Send via BitChat BinaryProtocol v2

    func broadcastTest(_ message: String) {
        guard let payload = message.data(using: .utf8) else { return }
        let packet = BitchatPacket(
            type: MessageType.message.rawValue,
            senderID: localPeerID,
            recipientID: nil,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            payload: payload,
            signature: nil,
            ttl: 5
        )
        broadcast(packet)
        let wireSize = packet.toBinaryData()?.count ?? 0
        addLog("SENT: \(message) (wire: \(wireSize)B, header: BinaryProtocol v2)")
    }

    private func broadcast(_ packet: BitchatPacket) {
        var p = packet
        p.ttl = adaptiveTTL()
        guard let encoded = p.toBinaryData() else {
            addLog("ERROR: BinaryProtocol.encode failed")
            return
        }

        let wireSize = encoded.count
        if wireSize <= 469 {
            sendToAll(encoded)
        } else {
            let chunks = FragmentCodec.fragment(encoded, maxSize: 469)
            addLog("Fragmenting \(wireSize)B → \(chunks.count) chunks")
            for chunk in chunks { sendToAll(chunk) }
        }
    }

    private func adaptiveTTL() -> UInt8 {
        let count = connectedPeerCount
        switch count { case 0...3: return 5; case 4...6: return 3; default: return 2 }
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

    /// BitChat receive pipeline: fragment → decode → dedup → relay → deliver.
    private func handleIncoming(_ data: Data, from peerUUID: UUID) {
        // Step 1: Fragment reassembly
        if FragmentCodec.isFragment(data) {
            guard let assembled = fragmentAssembly.addFragment(data, from: peerUUID) else { return }
            handleIncoming(assembled, from: peerUUID)
            return
        }
        // Step 2: Decode via BitChat BinaryProtocol
        guard let packet = BitchatPacket.from(data) else {
            addLog("ERROR: BinaryProtocol.decode failed (\(data.count)B)")
            return
        }
        // Step 3: Dedup
        let dedupKey = "\(packet.senderID.hex)-\(packet.timestamp)-\(packet.type)"
        guard deduplicator.isNew(dedupKey) else { return }

        // Display
        let sender = packet.senderID.hex.prefix(8)
        let payloadStr = String(data: packet.payload, encoding: .utf8) ?? "\(packet.payload.count)B"
        addLog("RECV [\(sender)]: \(payloadStr) (TTL=\(packet.ttl), type=0x\(String(format:"%02x",packet.type)))")

        // Step 4: Flood relay
        if packet.ttl > 1 {
            var relayed = packet
            relayed.ttl = packet.ttl - 1
            if let encoded = relayed.toBinaryData() {
                sendToAll(encoded, excluding: peerUUID)
            }
        }
    }

    private func updatePeerCount() {
        connectedPeerCount = connectedPeripherals.count + subscribedCentrals.count
    }
}

// MARK: - CBCentralManagerDelegate
extension BLETestService: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state == .poweredOn {
                central.scanForPeripherals(withServices: [serviceUUID], options: [
                    CBCentralManagerScanOptionAllowDuplicatesKey: false
                ])
                addLog("Scanning for BitChat peers...")
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
                type: charUUID, properties: [.read, .write, .notify],
                value: nil, permissions: [.readable, .writeable]
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
            addLog("Advertising as \(name) (BitChat v2)")
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

// MARK: - Hex helper (local, avoids module dependency)
private extension Data {
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
