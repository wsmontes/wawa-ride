import SwiftUI
import CoreLocation
import MapLibre

/// Ride map using MapLibre Native directly (no SwiftUI DSL — avoids macro issues).
///
/// Uses UIViewRepresentable to wrap MLNMapView. Supports PMTiles via local
/// style URL for fully offline maps. Rider annotations update reactively.
public struct RideMapView: UIViewRepresentable {
    @Binding var riders: [RiderAnnotation]
    @Binding var routeCoords: [CLLocationCoordinate2D]
    let styleURL: URL

    public init(riders: Binding<[RiderAnnotation]>,
                routeCoords: Binding<[CLLocationCoordinate2D]>,
                styleURL: URL = defaultStyleURL()) {
        _riders = riders
        _routeCoords = routeCoords
        self.styleURL = styleURL
    }

    public func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: styleURL)
        map.delegate = context.coordinator
        map.setCenter(CLLocationCoordinate2D(latitude: 48.4284, longitude: -123.3656), zoomLevel: 13, animated: false)
        map.showsUserLocation = true
        map.userTrackingMode = .follow
        map.logoView.isHidden = true
        // OSM attribution required by ODbL
        map.attributionButton.isHidden = false
        return map
    }

    public func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.updateAnnotations(map: map, riders: riders)
        context.coordinator.updateRoute(map: map, coords: routeCoords)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public class Coordinator: NSObject, MLNMapViewDelegate {
        private var riderSources: [String: MLNShapeSource] = [:]
        private var routeSource: MLNShapeSource?

        // MARK: - MLNMapViewDelegate

        public func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            // We'll add sources and connect layers when data arrives
        }

        func updateAnnotations(map: MLNMapView, riders: [RiderAnnotation]) {
            guard let style = map.style else { return }

            // Build GeoJSON feature collection for riders
            var features: [MLNPointFeature] = []
            for rider in riders {
                let feature = MLNPointFeature()
                feature.coordinate = rider.coordinate
                feature.title = rider.displayName
                feature.attributes = [
                    "isLeader": rider.isLeader,
                    "id": rider.id
                ]
                features.append(feature)
            }

            let sourceID = "riders-source"
            if style.source(withIdentifier: sourceID) == nil {
                let source = MLNShapeSource(identifier: sourceID, features: features)
                style.addSource(source)

                // Self: blue dot
                let selfLayer = MLNCircleStyleLayer(identifier: "riders-self", source: source)
                selfLayer.circleRadius = NSExpression(forConstantValue: 12)
                selfLayer.circleColor = NSExpression(forConstantValue: UIColor.systemBlue)
                selfLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
                selfLayer.circleStrokeWidth = NSExpression(forConstantValue: 3)
                selfLayer.predicate = NSPredicate(format: "isLeader == YES")
                style.addLayer(selfLayer)

                // Others: orange dot
                let otherLayer = MLNCircleStyleLayer(identifier: "riders-other", source: source)
                otherLayer.circleRadius = NSExpression(forConstantValue: 12)
                otherLayer.circleColor = NSExpression(forConstantValue: UIColor.systemOrange)
                otherLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
                otherLayer.circleStrokeWidth = NSExpression(forConstantValue: 2)
                otherLayer.predicate = NSPredicate(format: "isLeader == NO")
                style.addLayer(otherLayer)
            } else if let source = style.source(withIdentifier: sourceID) as? MLNShapeSource {
                source.shape = MLNShapeCollectionFeature(shapes: features)
            }
        }

        func updateRoute(map: MLNMapView, coords: [CLLocationCoordinate2D]) {
            guard let style = map.style, coords.count > 1 else { return }

            var coordinates = coords
            let polyline = MLNPolyline(coordinates: &coordinates, count: UInt(coordinates.count))

            let sourceID = "route-source"
            if style.source(withIdentifier: sourceID) == nil {
                let source = MLNShapeSource(identifier: sourceID, shape: polyline)
                style.addSource(source)

                let layer = MLNLineStyleLayer(identifier: "route", source: source)
                layer.lineColor = NSExpression(forConstantValue: UIColor.systemBlue)
                layer.lineWidth = NSExpression(forConstantValue: 4)
                style.addLayer(layer)
            } else if let source = style.source(withIdentifier: sourceID) as? MLNShapeSource {
                source.shape = polyline
            }
        }
    }

    public static func defaultStyleURL() -> URL {
        OfflineTileManager().makeStyleURL()
    }
}

// MARK: - Data models

/// A rider's position on the map.
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
