import Foundation
import CoreLocation
import WawaMesh

/// Coordinates group navigation — leader shares route, followers track.
public final class GroupNavigationCoordinator: ObservableObject {
    @Published public var leaderTrail: [CLLocationCoordinate2D] = []
    @Published public var sharedRoute: [CLLocationCoordinate2D] = []

    private let mapMatching: MapMatchingService
    private var leaderPositions: [CLLocationCoordinate2D] = []

    public init(mapMatching: MapMatchingService) {
        self.mapMatching = mapMatching
    }

    /// Called when a locationUpdate packet arrives from the leader.
    public func appendLeaderPosition(_ coord: CLLocationCoordinate2D) {
        leaderPositions.append(coord)
        leaderTrail = leaderPositions
        // Periodically snap to road
        if leaderPositions.count % 10 == 0 { Task { await snapTrail() } }
    }

    /// Called when a routeShare packet arrives.
    public func setSharedRoute(_ coords: [CLLocationCoordinate2D]) {
        sharedRoute = coords
    }

    private func snapTrail() async {
        guard leaderPositions.count >= 5 else { return }
        if let matched = try? await mapMatching.matchTrace(coordinates: leaderPositions) {
            await MainActor.run { leaderTrail = matched.geometry }
        }
    }
}
