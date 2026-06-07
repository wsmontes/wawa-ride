import Foundation

// MARK: - Voice Alert (TTS)

struct VoiceAlert: Codable {
    let text: String
    let priority: VoiceAlertPriority
    let canInterrupt: Bool
    var repeatCount: Int
    let minInterval: TimeInterval
    let dedupKey: String
    var timesSpoken: Int = 0
    var spokenAt: Date?

    init(
        text: String,
        priority: VoiceAlertPriority = .normal,
        canInterrupt: Bool = false,
        repeatCount: Int = 1,
        minInterval: TimeInterval = 5,
        dedupKey: String,
        timesSpoken: Int = 0
    ) {
        self.text = text
        self.priority = priority
        self.canInterrupt = canInterrupt
        self.repeatCount = repeatCount
        self.minInterval = minInterval
        self.dedupKey = dedupKey
        self.timesSpoken = timesSpoken
    }

    func isStillRelevant() -> Bool {
        guard let spokenAt else { return true }
        return Date().timeIntervalSince(spokenAt) >= minInterval
    }
}

enum VoiceAlertPriority: Int, Codable, Comparable {
    case background = 0
    case normal = 1
    case high = 2
    case critical = 3

    static func < (lhs: VoiceAlertPriority, rhs: VoiceAlertPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
