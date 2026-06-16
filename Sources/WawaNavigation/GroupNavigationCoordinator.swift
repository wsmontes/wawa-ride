import Foundation
import CoreLocation
// import WawaMesh — flat target: types compiled in same module

/// Coordinates group navigation — leader shares route, followers track leader's trail.
///
/// Architecture inspired by Meshtastic Apple's group visualization:
/// https://github.com/meshtastic/Meshtastic-Apple (GPL — code NOT copied, only UX patterns)
/// Key UX patterns from Meshtastic:
/// - Distinguish direct-connected vs multi-hop nodes on map
/// - Show trail history (breadcrumb line)
/// - Leader/follower role distinction
///
/// Flow:
/// 1. Leader plans route (import GPX or request from Valhalla)
/// 2. Leader broadcasts route via mesh (.routeShare packet)
/// 3. Followers receive route → display on map → start following
/// 4. Leader's live GPS positions are map-matched periodically to produce clean trail
/// 5. If a follower deviates >100m from route, alert is triggered
///
/// Map matching (Valhalla Meili) is used to clean up noisy GPS traces:
/// - Raw mesh location updates arrive at 1 Hz with 5-50m accuracy
/// - Every 10 updates, we snap the accumulated points to the road network
/// - This produces a smooth trail line even with GPS jitter
///
/// See also:
/// - CoreGPX for importing leader's planned route: https://github.com/vincentneo/CoreGPX
/// - Turf-Swift for corridor deviation check: https://github.com/mapbox/turf-swift
public final class GroupNavigationCoordinator: ObservableObject {
    @Published public var leaderTrail: [CLLocationCoordinate2D] = []
    @Published public var sharedRoute: [CLLocationCoordinate2D] = []

    private let mapMatching: MapMatchingService
    private var leaderPositions: [CLLocationCoordinate2D] = []

    public init(mapMatching: MapMatchingService) {
        self.mapMatching = mapMatching
    }

    /// Called when a locationUpdate packet arrives from the leader.
    /// Accumulates positions and periodically snaps to road network.
    public func appendLeaderPosition(_ coord: CLLocationCoordinate2D) {
        leaderPositions.append(coord)
        leaderTrail = leaderPositions
        // Snap every 10 positions to produce clean trail
        if leaderPositions.count % 10 == 0 { Task { await snapTrail() } }
    }

    /// Called when a routeShare packet arrives (leader broadcast their planned route).
    public func setSharedRoute(_ coords: [CLLocationCoordinate2D]) {
        sharedRoute = coords
    }

    /// Snap accumulated GPS points to road network via Valhalla Meili.
    private func snapTrail() async {
        guard leaderPositions.count >= 5 else { return }
        if let matched = try? await mapMatching.matchTrace(coordinates: leaderPositions) {
            await MainActor.run { leaderTrail = matched.geometry }
        }
    }
}
