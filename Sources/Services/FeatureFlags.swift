import Foundation

// MARK: - Feature Flags

/// Controls visibility of unstable/experimental features for TestFlight V1.
/// All flags default to OFF. Enable for internal testing via Diagnostic screen.
/// Uses UserDefaults so flags survive app restart.

final class FeatureFlags {
    static let shared = FeatureFlags()

    // MARK: - V1 Public (always ON)

    // These are the core features. Always enabled.

    // MARK: - V1 Experimental (OFF by default)

    @UserDefault(key: "ff_walkie_talkie", defaultValue: false)
    var walkieTalkie: Bool

    @UserDefault(key: "ff_voice_commands", defaultValue: false)
    var voiceCommands: Bool

    @UserDefault(key: "ff_async_voice_messages", defaultValue: false)
    var asyncVoiceMessages: Bool

    @UserDefault(key: "ff_rooms", defaultValue: false)
    var rooms: Bool

    @UserDefault(key: "ff_mesh_relay", defaultValue: false)
    var meshRelay: Bool

    // MARK: - V1 Disabled (cut from public release)

    @UserDefault(key: "ff_turn_by_turn_nav", defaultValue: false)
    var turnByTurnNav: Bool

    @UserDefault(key: "ff_auto_pause", defaultValue: false)
    var autoPause: Bool

    @UserDefault(key: "ff_rerouting", defaultValue: false)
    var rerouting: Bool

    @UserDefault(key: "ff_elevation_profile", defaultValue: false)
    var elevationProfile: Bool

    @UserDefault(key: "ff_kml_import", defaultValue: false)
    var kmlImport: Bool

    @UserDefault(key: "ff_export_multi_apps", defaultValue: false)
    var exportMultiApps: Bool

    @UserDefault(key: "ff_private_rooms", defaultValue: false)
    var privateRooms: Bool

    @UserDefault(key: "ff_geo_uri", defaultValue: false)
    var geoURI: Bool

    // MARK: - Developer

    @UserDefault(key: "ff_show_diagnostics", defaultValue: true)
    var showDiagnostics: Bool

    func resetAll() {
        let keys = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix("ff_") }
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
    }
}

// MARK: - UserDefaults Property Wrapper

@propertyWrapper
struct UserDefault<T> {
    let key: String
    let defaultValue: T

    var wrappedValue: T {
        get { UserDefaults.standard.object(forKey: key) as? T ?? defaultValue }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
