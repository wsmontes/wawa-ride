import Foundation
import os.log

/// In-memory log buffer visible in the debug overlay.
final class AppLogger: ObservableObject, @unchecked Sendable {
    static let shared = AppLogger()

    @Published var entries: [LogEntry] = []
    private let maxEntries = 200

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: String
        let message: String
    }

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    func log(_ message: String, level: String = "info") {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        DispatchQueue.main.async {
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
            // Also write to file for remote retrieval
            self.writeToFile(entry)
        }
        os.Logger(subsystem: "com.wawaride", category: "app").log("[\(level)] \(message)")
    }

    private func writeToFile(_ entry: LogEntry) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        let line = "[\(f.string(from: entry.timestamp))] \(entry.level.uppercased()): \(entry.message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = logFileURL()
        if FileManager.default.fileExists(atPath: url.path) {
            if let fh = try? FileHandle(forWritingTo: url) {
                fh.seekToEndOfFile()
                fh.write(data)
                try? fh.close()
            }
        } else {
            try? data.write(to: url)
        }
    }

    private func logFileURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("wawa-ride.log")
    }

    var recentText: String {
        entries.suffix(50).reversed().map {
            "[\(formatter.string(from: $0.timestamp))] \($0.level.uppercased()): \($0.message)"
        }.joined(separator: "\n")
    }

    func info(_ msg: String)  { log(msg, level: "info") }
    func warn(_ msg: String)  { log(msg, level: "warn") }
    func error(_ msg: String) { log(msg, level: "ERROR") }
}
