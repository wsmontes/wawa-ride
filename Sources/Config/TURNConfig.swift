import Foundation

/// TURN/STUN configuration loaded from TURNConfig.plist (gitignored).
/// Template at TURNConfig.template.plist — copy and fill in real credentials.
enum TURNConfig {

    // MARK: - STUN (public, no auth required)

    static let stunURLs: [String] = [
        "stun:stun.l.google.com:19302",
        "stun:stun.relay.metered.ca:80"
    ]

    // MARK: - TURN (loaded from gitignored plist)

    static let turnURLs: [String] = [
        "turn:global.relay.metered.ca:80",
        "turn:global.relay.metered.ca:80?transport=tcp",
        "turn:global.relay.metered.ca:443",
        "turns:global.relay.metered.ca:443?transport=tcp"
    ]

    static var turnUsername: String { secrets["METERED_TURN_USERNAME"] ?? "" }
    static var turnCredential: String { secrets["METERED_TURN_CREDENTIAL"] ?? "" }
    static var meteredAPIKey: String { secrets["METERED_API_KEY"] ?? "" }

    // MARK: - Private

    private static let secrets: [String: String] = {
        guard let url = Bundle.main.url(forResource: "TURNConfig", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: String]
        else { return [:] }
        return dict
    }()
}
