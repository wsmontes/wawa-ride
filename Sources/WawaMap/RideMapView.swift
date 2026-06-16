import SwiftUI
import MapKit
import MapCache

/// Ride map using native MapKit with offline tile caching via MapCache.
///
/// MapCache automatically caches OpenStreetMap tiles to a single SQLite file
/// as the user browses. First use requires internet; subsequent uses work
/// offline for any previously-viewed areas. Cache persists across app launches.
///
/// Reference: https://github.com/merlos/MapCache (MIT, 120+ stars)
public struct RideMapView: UIViewRepresentable {
    @Binding var riders: [RiderAnnotation]
    @Binding var routeCoords: [CLLocationCoordinate2D]

    public init(riders: Binding<[RiderAnnotation]>,
                routeCoords: Binding<[CLLocationCoordinate2D]>) {
        _riders = riders
        _routeCoords = routeCoords
    }

    public func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        let center = CLLocationCoordinate2D(latitude: 48.4284, longitude: -123.3656)
        map.setRegion(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)), animated: false)

        // Offline cache: OSM tiles → SQLite, single file
        let cache = OfflineTileManager().makeCache()
        map.useCache(cache)

        return map
    }

    public func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.updateAnnotations(map: map, riders: riders)
        context.coordinator.updateRoute(map: map, coords: routeCoords)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public class Coordinator: NSObject, MKMapViewDelegate {
        private var lastRoute: MKPolyline?

        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = 4
                return renderer
            }
            // Delegate tile rendering to MapCache
            return mapView.mapCacheRenderer(forOverlay: overlay)
        }

        func updateAnnotations(map: MKMapView, riders: [RiderAnnotation]) {
            let currentIDs = Set(riders.map(\.id))
            let existingIDs = Set(map.annotations.compactMap { ($0 as? RiderPoint)?.riderId })

            // Remove stale
            let toRemove = map.annotations.filter { ann in
                guard let rp = ann as? RiderPoint else { return false }
                return !currentIDs.contains(rp.riderId)
            }
            map.removeAnnotations(toRemove)

            // Add or update
            for rider in riders {
                if let existing = map.annotations.first(where: { ($0 as? RiderPoint)?.riderId == rider.id }) as? RiderPoint {
                    existing.coordinate = rider.coordinate
                } else {
                    let point = RiderPoint(rider: rider)
                    map.addAnnotation(point)
                }
            }
        }

        func updateRoute(map: MKMapView, coords: [CLLocationCoordinate2D]) {
            if let last = lastRoute { map.removeOverlay(last) }
            guard coords.count > 1 else { return }
            let polyline = MKPolyline(coordinates: coords, count: coords.count)
            map.addOverlay(polyline)
            lastRoute = polyline
        }
    }
}

/// MKPointAnnotation subclass that carries rider identity.
class RiderPoint: MKPointAnnotation {
    let riderId: String

    init(rider: RiderAnnotation) {
        self.riderId = rider.id
        super.init()
        self.coordinate = rider.coordinate
        self.title = rider.displayName
    }
}

// MARK: - Data models (unchanged from MapLibre version)

public struct RiderAnnotation: Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public var coordinate: CLLocationCoordinate2D
    public var heading: Double?
    public var speed: Double?
    public var isLeader: Bool
    public var isMember: Bool
    public var lastSeen: Date

    public var isStale: Bool { Date().timeIntervalSince(lastSeen) > 15 }

    public init(id: String, displayName: String, coordinate: CLLocationCoordinate2D,
                heading: Double? = nil, speed: Double? = nil, isLeader: Bool = false,
                isMember: Bool = true, lastSeen: Date = Date()) {
        self.id = id; self.displayName = displayName; self.coordinate = coordinate
        self.heading = heading; self.speed = speed; self.isLeader = isLeader
        self.isMember = isMember; self.lastSeen = lastSeen
    }
}
