import SwiftUI
import MapLibre
import CoreLocation

/// MapLibre-based ride map showing riders, route line, and waypoints.
public struct RideMapView: UIViewRepresentable {
    @Binding var riders: [RiderAnnotation]
    @Binding var routeCoords: [CLLocationCoordinate2D]
    let styleURL: URL

    public init(riders: Binding<[RiderAnnotation]>,
                routeCoords: Binding<[CLLocationCoordinate2D]>,
                styleURL: URL = URL(string: "https://demotiles.maplibre.org/style.json")!) {
        _riders = riders
        _routeCoords = routeCoords
        self.styleURL = styleURL
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: styleURL)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.userTrackingMode = .followWithHeading
        return map
    }

    public func updateUIView(_ map: MLNMapView, context: Context) {
        guard map.style != nil else { return }
        context.coordinator.updateRiders(map: map, riders: riders)
        context.coordinator.updateRoute(map: map, coords: routeCoords)
    }

    public class Coordinator: NSObject, MLNMapViewDelegate {
        private var layersReady = false

        public func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            // Rider circles source + layer
            let riderSource = MLNShapeSource(identifier: "riders", shape: nil, options: nil)
            style.addSource(riderSource)
            let riderLayer = MLNCircleStyleLayer(identifier: "riders-layer", source: riderSource)
            riderLayer.circleRadius = NSExpression(forConstantValue: 14)
            riderLayer.circleColor = NSExpression(forConstantValue: UIColor.systemOrange)
            riderLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            riderLayer.circleStrokeWidth = NSExpression(forConstantValue: 2.5)
            style.addLayer(riderLayer)

            // Route line source + layer
            let routeSource = MLNShapeSource(identifier: "route", shape: nil, options: nil)
            style.addSource(routeSource)
            let routeLayer = MLNLineStyleLayer(identifier: "route-line", source: routeSource)
            routeLayer.lineColor = NSExpression(forConstantValue: UIColor.systemBlue)
            routeLayer.lineWidth = NSExpression(forConstantValue: 4)
            routeLayer.lineCap = NSExpression(forConstantValue: "round")
            style.addLayer(routeLayer)

            layersReady = true
        }

        func updateRiders(map: MLNMapView, riders: [RiderAnnotation]) {
            guard layersReady, let src = map.style?.source(withIdentifier: "riders") as? MLNShapeSource else { return }
            let features = riders.map { r -> MLNPointFeature in
                let f = MLNPointFeature()
                f.coordinate = r.coordinate
                f.attributes = ["name": r.displayName]
                return f
            }
            src.shape = MLNShapeCollectionFeature(shapes: features)
        }

        func updateRoute(map: MLNMapView, coords: [CLLocationCoordinate2D]) {
            guard layersReady, let src = map.style?.source(withIdentifier: "route") as? MLNShapeSource else { return }
            guard !coords.isEmpty else { src.shape = nil; return }
            var c = coords
            src.shape = MLNPolyline(coordinates: &c, count: UInt(c.count))
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

    public init(id: String, displayName: String, coordinate: CLLocationCoordinate2D,
                heading: Double? = nil, speed: Double? = nil, isLeader: Bool = false) {
        self.id = id; self.displayName = displayName; self.coordinate = coordinate
        self.heading = heading; self.speed = speed; self.isLeader = isLeader
    }
}
