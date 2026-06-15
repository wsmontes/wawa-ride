import UIKit
@preconcurrency import CoreBluetooth
import os.log

final class BLEPairingService: NSObject, ObservableObject, @unchecked Sendable {

    @Published var isScanning = false
    @Published var isAdvertising = false
    @Published var discoveredPeers: [BLEPeer] = []
    @Published var connectedPeer: BLEPeer?

    struct BLEPeer: Identifiable, Hashable {
        let id: UUID; let name: String
    }

    var onPeerConnected: ((String) -> Void)?
    var onDataReceived: ((Data, String) -> Void)?
    /// Called when IP:port info is received from a peer (triggers TCP connection)
    var onPeerInfoReceived: ((String, UInt16) -> Void)?

    // MARK: - BLE

    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!
    private var connectedPeripheral: CBPeripheral?
    private var subscribedCentrals: [CBCentral] = []
    private var txCharacteristic: CBMutableCharacteristic?

    private let serviceUUID = CBUUID(string: "E20A39F4-73F5-4BC4-A12F-17D1AD07A961")
    private let charUUID    = CBUUID(string: "08590F7E-DB05-467E-8757-72F6FAEB13D4")
    private let log = Logger(subsystem: "com.wawaride", category: "BLE")

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
    }

    func start() {
        AppLogger.shared.info("BLE: starting")
        isScanning = true
        isAdvertising = true
        if centralManager.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
        }
    }

    func stop() {
        centralManager.stopScan()
        peripheralManager.stopAdvertising()
        isScanning = false
        isAdvertising = false
    }

    /// Send data bidirectionally (works whether we're central or peripheral)
    func send(_ data: Data) {
        var sent = false
        // Central → Peripheral write
        if let p = connectedPeripheral, let services = p.services {
            for s in services where s.uuid == serviceUUID {
                for c in s.characteristics ?? [] where c.uuid == charUUID {
                    p.writeValue(data, for: c, type: .withResponse)
                    AppLogger.shared.info("BLE sent \(data.count)b → central write")
                    sent = true
                }
            }
        }
        // Peripheral → Central update (also try this path)
        if let tx = txCharacteristic, !subscribedCentrals.isEmpty {
            let ok = peripheralManager.updateValue(data, for: tx, onSubscribedCentrals: subscribedCentrals)
            AppLogger.shared.info("BLE sent \(data.count)b → peripheral update: \(ok ? "OK" : "FULL")")
            sent = true
        }
        if !sent {
            AppLogger.shared.error("BLE send FAILED — no channel (cp:\(connectedPeripheral != nil) sc:\(subscribedCentrals.count))")
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEPairingService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        AppLogger.shared.info("BLE central: \(central.state.rawValue)")
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: [serviceUUID], options: nil)
            isScanning = true
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? "BLE-\(peripheral.identifier.uuidString.prefix(4))"
        AppLogger.shared.info("BLE discovered: \(name)")
        let peer = BLEPeer(id: peripheral.identifier, name: name)
        DispatchQueue.main.async {
            if !self.discoveredPeers.contains(peer) { self.discoveredPeers.append(peer) }
            if self.connectedPeripheral == nil {
                self.connectedPeripheral = peripheral
                central.stopScan()
                central.connect(peripheral, options: nil)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        AppLogger.shared.info("BLE connected central→: \(peripheral.name ?? "?")")
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        AppLogger.shared.warn("BLE disconnected: \(error?.localizedDescription ?? "ok")")
        DispatchQueue.main.async { self.connectedPeer = nil; self.connectedPeripheral = nil }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEPairingService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for s in services where s.uuid == serviceUUID {
            peripheral.discoverCharacteristics([charUUID], for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for c in chars where c.uuid == charUUID {
            peripheral.setNotifyValue(true, for: c)
            let name = peripheral.name ?? peripheral.identifier.uuidString
            DispatchQueue.main.async {
                self.connectedPeer = BLEPeer(id: peripheral.identifier, name: name)
                AppLogger.shared.info("BLE ready — peer: \(name)")
                self.onPeerConnected?(name)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        let name = peripheral.name ?? peripheral.identifier.uuidString
        AppLogger.shared.info("BLE recv \(data.count)b via notify from \(name)")
        onDataReceived?(data, name)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let err = error {
            AppLogger.shared.error("BLE write failed: \(err.localizedDescription)")
        }
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLEPairingService: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        AppLogger.shared.info("BLE peripheral: \(peripheral.state.rawValue)")
        if peripheral.state == .poweredOn {
            let service = CBMutableService(type: serviceUUID, primary: true)
            let characteristic = CBMutableCharacteristic(
                type: charUUID,
                properties: [.read, .write, .notify],
                value: nil,
                permissions: [.readable, .writeable]
            )
            service.characteristics = [characteristic]
            txCharacteristic = characteristic
            peripheralManager.add(service)
            peripheralManager.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
                CBAdvertisementDataLocalNameKey: UIDevice.current.name
            ])
            isAdvertising = true
            AppLogger.shared.info("BLE advertising started")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        AppLogger.shared.info("BLE central subscribed: \(central.identifier.uuidString.prefix(4))")
        subscribedCentrals.append(central)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           didReceiveWrite requests: [CBATTRequest]) {
        for req in requests {
            if let data = req.value {
                let name = req.central.identifier.uuidString
                AppLogger.shared.info("BLE recv \(data.count)b via write from \(name.prefix(8)) — PONG check: \(String(data: data.prefix(5), encoding: .utf8) ?? "?")")
                onDataReceived?(data, name)
            }
            peripheral.respond(to: req, withResult: .success)
        }
    }
}
