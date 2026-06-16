import Foundation
@preconcurrency import CoreBluetooth

/// WawaRide BLE mesh service using BitChat BinaryProtocol v2.
///
/// Reuses the proven implementation from BLETestService.
/// This file is temporary — it will be replaced by TransportCoordinator
/// once the full app build is complete.
@MainActor
final class MeshService: NSObject, ObservableObject, @unchecked Sendable {
    @Published var connectedPeerCount = 0
    @Published var isRunning = false
    @Published var lastMessage: String = "—"

    /// Called when a text message is received: (senderPeerID, text)
    var onMessageReceived: ((String, String) -> Void)?

    private let serviceUUID = CBUUID(string: "A1B2C3D4-5E6F-7A8B-9C0D-E1F2A3B4C5D6")
    private let charUUID    = CBUUID(string: "B2C3D4E5-6F7A-8B9C-0D1E-F2A3B4C5D6E7")

    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!
    private var txCharacteristic: CBMutableCharacteristic?
    private var connectedPeripherals: [UUID: CBPeripheral] = [:]
    private var subscribedCentrals: [CBCentral] = []
    private let fragmentAssembly = FragmentAssemblyBuffer()
    private let deduplicator = MessageDeduplicator()

    let localPeerID: Data = {
        let key = "wawa_mesh_peer_id"
        if let saved = UserDefaults.standard.data(forKey: key), saved.count == 8 { return saved }
        var id = Data(count: 8)
        _ = id.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 8, $0.baseAddress!) }
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    var localPeerIDHex: String { localPeerID.map { String(format: "%02x", $0) }.joined() }

    func start() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        isRunning = true
    }

    func stop() {
        centralManager.stopScan()
        peripheralManager.stopAdvertising()
        connectedPeripherals.values.forEach { centralManager.cancelPeripheralConnection($0) }
        connectedPeripherals.removeAll()
        subscribedCentrals.removeAll()
        isRunning = false
        connectedPeerCount = 0
    }

    func broadcastTest(_ message: String) {
        guard let payload = message.data(using: .utf8) else { return }
        let packet = BitchatPacket(
            type: MessageType.message.rawValue,
            senderID: localPeerID, recipientID: nil,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            payload: payload, signature: nil, ttl: 5
        )
        guard let encoded = packet.toBinaryData() else { return }
        if encoded.count <= 469 { sendToAll(encoded) }
        else { for chunk in FragmentCodec.fragment(encoded, maxSize: 469) { sendToAll(chunk) } }
    }

    func sendPacket(type: UInt8, payload: Data) {
        let packet = BitchatPacket(
            type: type,
            senderID: localPeerID,
            recipientID: nil,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            payload: payload,
            signature: nil,
            ttl: 5
        )
        guard let encoded = packet.toBinaryData() else { return }
        if encoded.count <= 469 {
            sendToAll(encoded)
        } else {
            for chunk in FragmentCodec.fragment(encoded, maxSize: 469) {
                sendToAll(chunk)
            }
        }
    }

    func sendToAll(_ data: Data, excluding: UUID? = nil) {
        for (id, p) in connectedPeripherals where id != excluding {
            if let svc = p.services?.first(where: { $0.uuid == serviceUUID }),
               let ch = svc.characteristics?.first(where: { $0.uuid == charUUID }) {
                p.writeValue(data, for: ch, type: .withResponse)
            }
        }
        if let tx = txCharacteristic, !subscribedCentrals.isEmpty {
            peripheralManager.updateValue(data, for: tx, onSubscribedCentrals: subscribedCentrals)
        }
    }

    private func handleIncoming(_ data: Data, from peerUUID: UUID) {
        if FragmentCodec.isFragment(data) {
            guard let assembled = fragmentAssembly.addFragment(data, from: peerUUID) else { return }
            handleIncoming(assembled, from: peerUUID); return
        }
        guard let packet = BitchatPacket.from(data) else { return }
        let key = "\(packet.senderID.hex)-\(packet.timestamp)-\(packet.type)"
        guard deduplicator.isNew(key) else { return }
        let text = String(data: packet.payload, encoding: .utf8) ?? "\(packet.payload.count)B"
        let peerId = packet.senderID.hex
        lastMessage = "[\(peerId.prefix(6))] \(text)"
        onMessageReceived?(peerId, text)
        if packet.ttl > 1 {
            var r = packet; r.ttl -= 1
            if let e = r.toBinaryData() { sendToAll(e, excluding: peerUUID) }
        }
    }

    private func updatePeerCount() { connectedPeerCount = connectedPeripherals.count + subscribedCentrals.count }
}

// MARK: - BLE Delegates
extension MeshService: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state == .poweredOn {
                central.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            }
        }
    }
    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        _ = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "?"
        Task { @MainActor in
            guard connectedPeripherals[peripheral.identifier] == nil, connectedPeripherals.count < 6 else { return }
            connectedPeripherals[peripheral.identifier] = peripheral
            central.connect(peripheral, options: nil)
        }
    }
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            peripheral.delegate = self
            peripheral.discoverServices([serviceUUID])
            updatePeerCount()
        }
    }
    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectedPeripherals.removeValue(forKey: peripheral.identifier)
            updatePeerCount()
            if central.state == .poweredOn { central.scanForPeripherals(withServices: [serviceUUID], options: nil) }
        }
    }
}

extension MeshService: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let svc = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else { return }
            peripheral.discoverCharacteristics([charUUID], for: svc)
        }
    }
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard let ch = service.characteristics?.first(where: { $0.uuid == charUUID }) else { return }
            peripheral.setNotifyValue(true, for: ch)
        }
    }
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard let data = characteristic.value else { return }
            handleIncoming(data, from: peripheral.identifier)
        }
    }
}

extension MeshService: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        Task { @MainActor in
            guard peripheral.state == .poweredOn else { return }
            let ch = CBMutableCharacteristic(type: charUUID, properties: [.read, .write, .notify], value: nil, permissions: [.readable, .writeable])
            let svc = CBMutableService(type: serviceUUID, primary: true)
            svc.characteristics = [ch]
            txCharacteristic = ch
            peripheralManager.add(svc)
            peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceUUID], CBAdvertisementDataLocalNameKey: "Wawa-\(localPeerIDHex.prefix(4))"])
        }
    }
    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        Task { @MainActor in
            subscribedCentrals.append(central)
            updatePeerCount()
        }
    }
    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        Task { @MainActor in
            subscribedCentrals.removeAll { $0.identifier == central.identifier }
            updatePeerCount()
        }
    }
    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        let items: [(Data?, UUID)] = requests.map { ($0.value, $0.central.identifier) }
        for req in requests { peripheral.respond(to: req, withResult: .success) }
        Task { @MainActor in for (data, cid) in items { if let data { handleIncoming(data, from: cid) } } }
    }
}

// Data.hex provided by BitFoundation/Data+Hex.swift
