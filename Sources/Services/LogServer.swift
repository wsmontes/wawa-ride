import Foundation
import Network
import os.log

/// Tiny HTTP server serving live app logs on the local WiFi IP.
final class LogServer: @unchecked Sendable {
    static let shared = LogServer()
    private var listener: NWListener?
    private(set) var url: String = ""

    func start() {
        do {
            listener = try NWListener(using: .tcp, on: 0)
            listener?.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                if case .ready = state, let port = self.listener?.port {
                    self.url = "http://\(self.localIP()):\(port)"
                    DispatchQueue.main.async {
                        AppLogger.shared.info("📡 Log: \(self.url)")
                    }
                }
            }
            listener?.newConnectionHandler = { [weak self] conn in
                conn.stateUpdateHandler = { [weak self] state in
                    guard case .ready = state else { return }
                    let html = """
                    <!DOCTYPE html><html><head><meta charset="utf-8"><title>Wawa Logs</title>
                    <meta http-equiv="refresh" content="1">
                    <style>body{font:12px monospace;background:#111;color:#0f0;padding:10px;white-space:pre-wrap}</style></head>
                    <body>\(AppLogger.shared.recentText.htmlEscaped)</body></html>
                    """
                    let resp = """
                    HTTP/1.1 200 OK\r
                    Content-Type: text/html; charset=utf-8\r
                    Content-Length: \(html.utf8.count)\r
                    Connection: close\r
                    \r
                    \(html)
                    """
                    conn.send(content: resp.data(using: .utf8), completion: .idempotent)
                    conn.cancel()
                }
                conn.start(queue: .main)
            }
            listener?.start(queue: .main)
        } catch {}
    }

    private func localIP() -> String {
        var addr = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return addr }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let name = ptr?.pointee.ifa_name,
                  let sa = ptr?.pointee.ifa_addr,
                  sa.pointee.sa_family == UInt8(AF_INET),
                  String(cString: name) == "en0" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            addr = String(cString: host)
        }
        return addr
    }
}

extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
    }
}

extension NWConnection {
    func send(content: Data?, completion: NWConnection.SendCompletion) {
        guard let data = content else { return }
        self.send(content: data, completion: completion)
    }
}
