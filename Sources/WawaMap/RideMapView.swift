import SwiftUI
import CoreLocation
import MapLibreSwiftUI
import MapLibre

/// Ride map using MapLibre SwiftUI-DSL (official wrapper).
/// Supports PMTiles via local file:// style URL.
///
/// MapLibre SwiftUI-DSL: https://github.com/maplibre/swiftui-dsl (BSD-3, 105 stars)
/// Provides declarative MapView, camera bindings, layer DSL, and CarPlay support.
///
/// PMTiles integration (confirmed working MapLibre iOS v6.10+):
/// - Style JSON references local file: `"url": "pmtiles://basemap.pmtiles"`
/// - File must be in app bundle or Documents directory
/// - MapLibre reads tiles directly from the flat binary (no server needed)
/// - Reference: https://docs.protomaps.com/pmtiles/maplibre
///
/// Rider annotations use data-driven styling:
/// - Active riders: orange circles (full opacity)
/// - Stale riders (>15s no update): gray circles at 50% opacity
/// - Leader: blue circle with star icon
/// Pattern inspired by Meshtastic Apple (GPL — UX only, no code copied):
/// - Direct vs multi-hop node distinction on map
/// - Connection quality indicators
/// Reference: https://github.com/meshtastic/Meshtastic-Apple
///
/// OSM Attribution (ODbL legal requirement):
/// Must display "© OpenStreetMap contributors" when using OSM-derived tiles.
/// Reference: https://www.openstreetmap.org/copyright
public struct RideMapView: View {
    @Binding var riders: [RiderAnnotation]
    @Binding var routeCoords: [CLLocationCoordinate2D]
    @State private var camera: MapViewCamera = .trackUserLocation(zoom: 14, pitch: .free)

    let styleURL: URL

    public init(riders: Binding<[RiderAnnotation]>,
                routeCoords: Binding<[CLLocationCoordinate2D]>,
                styleURL: URL = defaultStyleURL()) {
        _riders = riders
        _routeCoords = routeCoords
        self.styleURL = styleURL
    }

    public var body: some View {
        MapView(styleURL: styleURL, camera: $camera) {
            // Route polyline
            if !routeCoords.isEmpty {
                MapPolyline(coordinates: routeCoords)
                    .stroke(.blue, lineWidth: 4)
            }
            // Rider markers
            ForEvery(riders) { rider in
                MapMarker(coordinate: rider.coordinate) {
                    RiderBadge(name: rider.displayName, isStale: rider.isStale, isLeader: rider.isLeader)
                }
            }
        }
        .mapControls {
            CompassView()
            UserLocationButton()
        }
        .ignoresSafeArea()
        // OSM attribution (ODbL requirement)
        .overlay(alignment: .bottomTrailing) {
            Text("© OpenStreetMap")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(4)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                .padding(8)
        }
    }

    /// Default style URL — uses bundled PMTiles if available, otherwise demo tiles.
    public static func defaultStyleURL() -> URL {
        if let local = Bundle.main.url(forResource: "style", withExtension: "json") {
            return local
        }
        return URL(string: "https://demotiles.maplibre.org/style.json")!
    }
}

/// Compact rider badge for map annotations.
struct RiderBadge: View {
    let name: String
    let isStale: Bool
    let isLeader: Bool

    var body: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(isStale ? .gray : (isLeader ? .blue : .orange))
                .opacity(isStale ? 0.5 : 1.0)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: isLeader ? "star.fill" : "motorcycle")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            Text(name)
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 4)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

/// A rider's position on the map.
public struct RiderAnnotation: Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public var coordinate: CLLocationCoordinate2D
    public var heading: Double?
    public var speed: Double?
    public var isLeader: Bool
    public var lastSeen: Date

    public var isStale: Bool { Date().timeIntervalSince(lastSeen) > 15 }

    public init(id: String, displayName: String, coordinate: CLLocationCoordinate2D,
                heading: Double? = nil, speed: Double? = nil, isLeader: Bool = false,
                lastSeen: Date = Date()) {
        self.id = id; self.displayName = displayName; self.coordinate = coordinate
        self.heading = heading; self.speed = speed; self.isLeader = isLeader; self.lastSeen = lastSeen
    }
}
