import Foundation

// MARK: - Persistent Logger

/// Writes diagnostic logs to a file for post-ride analysis.
/// Accessible via DiagnosticView → Share Sheet.

final class Logger {
    static let shared = Logger()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.wawa.logger")
    private let dateFormatter: DateFormatter
    private let maxFileSize = 1_000_000 // 1MB

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("wawa_debug.log")
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }

    // MARK: - Logging

    func log(_ message: String, category: String = "general") {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)][\(category)] \(message)\n"

        queue.async { [self] in
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: fileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? data.write(to: fileURL)
                }
                // Rotate if too large
                if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                   let size = attrs[.size] as? Int, size > maxFileSize {
                    rotateLog()
                }
            }
        }
    }

    // Convenience methods
    func mesh(_ message: String) { log(message, category: "mesh") }
    func gps(_ message: String) { log(message, category: "gps") }
    func audio(_ message: String) { log(message, category: "audio") }
    func nav(_ message: String) { log(message, category: "nav") }
    func ride(_ message: String) { log(message, category: "ride") }

    // MARK: - File Management

    var logFileURL: URL { fileURL }

    var logContents: String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "No logs yet"
    }

    var logSize: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int else { return "0 KB" }
        if size > 1_000_000 { return "\(size / 1_000_000) MB" }
        if size > 1000 { return "\(size / 1000) KB" }
        return "\(size) B"
    }

    func clearLogs() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func rotateLog() {
        let backup = fileURL.deletingPathExtension().appendingPathExtension("old.log")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }
}

// MARK: - Global log function (replaces print)

func wawaLog(_ message: String, category: String = "general") {
    Logger.shared.log(message, category: category)
    #if DEBUG
    print("[\(category)] \(message)")
    #endif
}
