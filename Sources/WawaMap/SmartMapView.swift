import SwiftUI
import MapKit
import MapCache

/// Smart map with speed-based zoom, manual override detection, and tile caching.
///
/// - Zoom adapts to speed: close when slow, far when fast
/// - Detects manual pan/zoom and shows re-center button
/// - Pre-caches tiles around current position
public struct SmartMapView: UIViewRepresentable {
    @Binding var riders: [RiderAnnotation]
    @Binding var routeCoords: [CLLocationCoordinate2D]
    @Binding var speedKmh: Double
    @Binding var isAutoCentered: Bool

    public init(riders: Binding<[RiderAnnotation]>,
                routeCoords: Binding<[CLLocationCoordinate2D]>,
                speedKmh: Binding<Double>,
                isAutoCentered: Binding<Bool>) {
        _riders = riders
        _routeCoords = routeCoords
        _speedKmh = speedKmh
        _isAutoCentered = isAutoCentered
    }

    public func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.setCenter(CLLocationCoordinate2D(latitude: 48.4284, longitude: -123.3656), animated: false)

        // MapCache for offline tiles (single SQLite file)
        var config = MapCacheConfig()
        config.cacheName = "WawaMapCache"
        config.capacity = 100 * 1024 * 1024
        let cache = MapCache(withConfig: config)
        map.useCache(cache)
        context.coordinator.cache = cache
        context.coordinator.map = map

        // Listen for re-center tap to force update
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.didReceiveReCenter),
            name: .userDidTapReCenter,
            object: nil
        )

        return map
    }

    public func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.updateAnnotations(map: map, riders: riders)
        context.coordinator.updateRoute(map: map, coords: routeCoords)

        // Auto-center: first location, speed change, or re-center button tapped
        if isAutoCentered, let userLoc = map.userLocation.location {
            let distance = distanceForSpeed(speedKmh)
            // Reset when transitioning from manual back to auto
            if context.coordinator.wasManual {
                context.coordinator.lastAutoCenterDistance = 0
                context.coordinator.wasManual = false
            }
            let lastDist = context.coordinator.lastAutoCenterDistance
            let shouldUpdate = !context.coordinator.hasInitialCentered || lastDist == 0 || abs(distance - lastDist) > 50
            if shouldUpdate {
                let region = MKCoordinateRegion(
                    center: userLoc.coordinate,
                    latitudinalMeters: distance,
                    longitudinalMeters: distance
                )
                context.coordinator.isProgrammaticChange = true
                context.coordinator.lastAutoCenterDistance = distance
                map.setRegion(region, animated: true)
            }
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // Speed → meters mapping
    private func distanceForSpeed(_ kmh: Double) -> CLLocationDistance {
        switch kmh {
        case ..<10:  return 200   // stopped/creeping
        case ..<50:  return 500   // urban
        case ..<100: return 1000  // highway
        default:     return 2000  // fast highway
        }
    }

    // MARK: - Coordinator

    public class Coordinator: NSObject, MKMapViewDelegate {
        var cache: MapCache?
        weak var map: MKMapView?
        private var lastRoute: MKPolyline?
        var isProgrammaticChange = false
        var lastAutoCenterDistance: CLLocationDistance = 0
        var wasManual = false
        var hasInitialCentered = false
        var mapReadyTime: Date?

        @objc func didReceiveReCenter() {
            wasManual = true
            lastAutoCenterDistance = 0
        }

        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: polyline)
                r.strokeColor = .systemBlue
                r.lineWidth = 4
                return r
            }
            return mapView.mapCacheRenderer(forOverlay: overlay)
        }

        /// Detect manual pan/zoom — user gesture, after map is ready
        public func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if !animated && !isProgrammaticChange {
                // Only fire after initial setup is complete (2s grace period)
                if let ready = mapReadyTime, Date() > ready {
                    NotificationCenter.default.post(name: .userDidPanMap, object: nil)
                }
            }
        }

        /// Re-enable auto-tracking after programmatic change completes
        public func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            isProgrammaticChange = false
        }

        /// Auto-center on first user location fix
        public func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard !hasInitialCentered, let loc = userLocation.location else { return }
            hasInitialCentered = true
            let region = MKCoordinateRegion(center: loc.coordinate, latitudinalMeters: 200, longitudinalMeters: 200)
            isProgrammaticChange = true
            lastAutoCenterDistance = 200
            mapView.setRegion(region, animated: true)
            // Ignore any "user pan" events for 2 seconds after initial center
            mapReadyTime = Date().addingTimeInterval(2)
        }

        func updateAnnotations(map: MKMapView, riders: [RiderAnnotation]) {
            let curIDs = Set(riders.map(\.id))
            let toRemove = map.annotations.filter { ann in
                guard let rp = ann as? RiderPoint else { return false }
                return !curIDs.contains(rp.riderId)
            }
            map.removeAnnotations(toRemove)
            for rider in riders {
                if let ex = map.annotations.first(where: { ($0 as? RiderPoint)?.riderId == rider.id }) as? RiderPoint {
                    ex.coordinate = rider.coordinate
                } else {
                    map.addAnnotation(RiderPoint(rider: rider))
                }
            }
        }

        func updateRoute(map: MKMapView, coords: [CLLocationCoordinate2D]) {
            if let l = lastRoute { map.removeOverlay(l) }
            guard coords.count > 1 else { return }
            let p = MKPolyline(coordinates: coords, count: coords.count)
            map.addOverlay(p)
            lastRoute = p
        }

        /// Pre-cache tiles around a location for given zoom range
        func preCacheTiles(around center: CLLocationCoordinate2D, radiusKm: Double, minZoom: Int, maxZoom: Int) {
            guard let cache = cache else { return }
            let d = radiusKm / 111.0 // km to degrees
            guard let region = TileCoordsRegion(
                topLeftLatitude: center.latitude + d,
                topLeftLongitude: center.longitude - d,
                bottomRightLatitude: center.latitude - d,
                bottomRightLongitude: center.longitude + d,
                minZoom: UInt8(minZoom),
                maxZoom: UInt8(maxZoom)
            ) else { return }
            let _ = RegionDownloader(forRegion: region, mapCache: cache)
        }
    }
}

// MARK: - RiderPoint

class RiderPoint: MKPointAnnotation {
    let riderId: String
    init(rider: RiderAnnotation) {
        self.riderId = rider.id
        super.init()
        self.coordinate = rider.coordinate
        self.title = rider.displayName
    }
}

extension Notification.Name {
    static let userDidPanMap = Notification.Name("com.wawaride.userDidPanMap")
    static let userDidTapReCenter = Notification.Name("com.wawaride.userDidTapReCenter")
}

// MARK: - RiderAnnotation (shared model)

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
