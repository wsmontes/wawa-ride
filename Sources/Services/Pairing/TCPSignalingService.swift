import Foundation
import Network
import os.log

/// TCP-based signaling relay for WebRTC. After BLE exchanges IPs,
/// each device starts a TCP listener and connects to the other.
final class TCPSignalingService: ObservableObject, @unchecked Sendable {

    @Published var connections: [String: NWConnection] = [:]

    var onDataReceived: ((Data, String) -> Void)?
    var onPeerConnected: ((String) -> Void)?
    var onPeerDisconnected: ((String) -> Void)?

    private var listener: NWListener?
    private let port: UInt16
    private let log = Logger(subsystem: "com.wawaride", category: "TCPSig")

    init(port: UInt16 = 9743) {
        self.port = port
    }

    // MARK: - Server (listen for incoming)

    func startListener() {
        listener = try? NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        listener?.newConnectionHandler = { [weak self] conn in
            conn.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                if case .ready = state {
                    let peerName = self.peerName(from: conn)
                    self.log.info("TCP accepted: \(peerName)")
                    self.connections[peerName] = conn
                    self.receive(on: conn, peer: peerName)
                    DispatchQueue.main.async { self.onPeerConnected?(peerName) }
                }
                if case .failed = state {
                    self.connections.removeValue(forKey: self.peerName(from: conn))
                }
            }
            conn.start(queue: .main)
        }
        listener?.start(queue: .main)
        log.info("TCP listener started on port \(self.port)")
    }

    // MARK: - Client (connect to peer)

    func connect(to host: String, port: UInt16, peerName: String) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state {
                self.log.info("TCP connected to: \(peerName)")
                self.connections[peerName] = conn
                self.receive(on: conn, peer: peerName)
                DispatchQueue.main.async { self.onPeerConnected?(peerName) }
            }
            if case .failed = state {
                self.log.error("TCP to \(peerName) failed")
                self.connections.removeValue(forKey: peerName)
            }
        }
        conn.start(queue: .main)
    }

    // MARK: - Send

    func send(_ data: Data, to peer: String) {
        guard let conn = connections[peer] else {
            log.warning("No TCP connection for \(peer)")
            return
        }
        // Prefix with 4-byte length (big-endian)
        var len = UInt32(data.count).bigEndian
        let header = Data(bytes: &len, count: 4)
        conn.send(content: header + data, completion: .contentProcessed({ err in
            if let err {
                self.log.error("TCP send error: \(err.localizedDescription)")
            }
        }))
    }

    func broadcast(_ data: Data) {
        for (peer, _) in connections {
            send(data, to: peer)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for (_, conn) in connections { conn.cancel() }
        connections.removeAll()
    }

    // MARK: - Receive (length-prefixed)

    private func receive(on conn: NWConnection, peer: String) {
        // Read 4-byte length header
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, err in
            guard let self, let data = data, data.count == 4, err == nil else {
                if let err { self?.log.error("TCP recv header: \(err.localizedDescription)") }
                return
            }
            let len = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard len > 0, len < 65536 else { return }
            // Read body
            conn.receive(minimumIncompleteLength: Int(len), maximumLength: Int(len)) { [weak self] body, _, _, err in
                guard let self, let body = body, err == nil else { return }
                self.log.debug("TCP recv \(body.count)b from \(peer)")
                self.onDataReceived?(body, peer)
                // Continue reading next message
                self.receive(on: conn, peer: peer)
            }
        }
    }

    private func peerName(from conn: NWConnection) -> String {
        if case .hostPort(let host, let port) = conn.currentPath?.remoteEndpoint {
            return "\(host):\(port)"
        }
        return "unknown"
    }
}
