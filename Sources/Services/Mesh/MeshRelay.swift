import Foundation

// MARK: - Mesh Relay (Store-and-Forward + Dedup)

final class MeshRelay {
    private var processedIDs: [String: Date] = [:]
    private let maxProcessed = 2000
    private let dedupTTL: TimeInterval = 300 // 5 minutes

    func hasSeen(_ messageId: String) -> Bool {
        cleanupExpired()
        if processedIDs[messageId] != nil { return true }
        return LocalStore.shared.hasMeshMessage(messageId)
    }

    func markSeen(_ messageId: String) {
        cleanupExpired()
        processedIDs[messageId] = Date()
        LocalStore.shared.insertMeshDedup(messageId)

        // Evict oldest if over max
        if processedIDs.count > maxProcessed {
            let sorted = processedIDs.sorted { $0.value < $1.value }
            for (key, _) in sorted.prefix(maxProcessed / 2) {
                processedIDs.removeValue(forKey: key)
            }
        }
    }

    private func cleanupExpired() {
        let cutoff = Date().addingTimeInterval(-dedupTTL)
        processedIDs = processedIDs.filter { $0.value > cutoff }
    }
}
