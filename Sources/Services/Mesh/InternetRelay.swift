import Foundation
import Network

// MARK: - Internet Relay (P2P over IP)

/// Zero-server internet relay: one device acts as TCP hub.
/// Other devices connect directly to it via IP.
///
/// Flow: BLE handshake → exchange relay info → BLE drops →
///       fall back to direct TCP connection over internet.
///
/// Limitations: NAT may block direct connections. If it fails, BLE is the fallback.

final class InternetRelay {
    static let shared = InternetRelay()
    static let servicePort: UInt16 = 45567

    private var listener: NWListener?
    private var connections: [String: NWConnection] = [:]
    private let queue = DispatchQueue(label: "com.wawa.relay")

    var isRelayActive = false
    var onRelayConnected: ((String) -> Void)?  // peerName
    var onRelayDisconnected: ((String) -> Void)?
    var onRelayData: ((Data, String) -> Void)?  // data, peerName

    private init() {}

    // MARK: - Start as Hub (server)

    func startAsHub() throws {
        guard !isRelayActive else { return }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.servicePort)!)
        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready: wawaLog("InternetRelay: hub ready on port \(Self.servicePort)", category: "mesh")
            case .failed(let err): wawaLog("InternetRelay: hub failed: \(err)", category: "mesh")
            default: break
            }
        }
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleIncomingConnection(connection)
        }
        listener?.start(queue: queue)
        isRelayActive = true
        wawaLog("InternetRelay: started as hub", category: "mesh")
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                let peerName = "relay-\(UUID().uuidString.prefix(4))"
                self?.connections[peerName] = connection
                DispatchQueue.main.async { self?.onRelayConnected?(peerName) }
                self?.receiveFrom(connection, peerName: peerName)
                wawaLog("InternetRelay: client connected", category: "mesh")
            case .failed, .cancelled:
                for (name, conn) in self?.connections ?? [:] where conn === connection {
                    self?.connections.removeValue(forKey: name)
                    DispatchQueue.main.async { self?.onRelayDisconnected?(name) }
                }
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveFrom(_ connection: NWConnection, peerName: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            if let data, !data.isEmpty {
                DispatchQueue.main.async { self?.onRelayData?(data, peerName) }
                self?.forwardToAll(data: data, except: peerName)
                self?.receiveFrom(connection, peerName: peerName)
            } else if error != nil {
                self?.connections.removeValue(forKey: peerName)
            }
        }
    }

    private func forwardToAll(data: Data, except senderName: String) {
        for (name, conn) in connections where name != senderName {
            conn.send(content: data, completion: .contentProcessed({ _ in }))
        }
    }

    // MARK: - Connect to Hub (client)

    func connectToHub(host: String) {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: Self.servicePort)!,
            using: .tcp
        )
        let peerName = "relay-\(host)"
        connections[peerName] = connection

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                DispatchQueue.main.async { self?.onRelayConnected?(peerName) }
                self?.receiveFrom(connection, peerName: peerName)
                wawaLog("InternetRelay: connected to hub \(host)", category: "mesh")
            case .failed, .cancelled:
                self?.connections.removeValue(forKey: peerName)
                DispatchQueue.main.async { self?.onRelayDisconnected?(peerName) }
            default: break
            }
        }
        connection.start(queue: queue)
    }

    // MARK: - Send

    func sendToAll(_ data: Data) {
        for (_, conn) in connections {
            conn.send(content: data, completion: .contentProcessed({ _ in }))
        }
    }

    // MARK: - Stop

    func stopRelay() {
        listener?.cancel()
        listener = nil
        for (_, conn) in connections { conn.cancel() }
        connections.removeAll()
        isRelayActive = false
    }

    // MARK: - Utility

    /// Get local WiFi IP address for other devices to connect to
    static func localWiFiIP() -> String? {
        var addr: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addrFamily = ptr.pointee.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) && (flags & (IFF_UP|IFF_RUNNING)) != 0 {
                let name = String(cString: ptr.pointee.ifa_name)
                if name == "en0" { // WiFi
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    addr = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        return addr
    }

    var connectedPeerCount: Int { connections.count }
}
