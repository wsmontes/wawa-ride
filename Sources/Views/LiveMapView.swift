import SwiftUI
import MapKit
import UIKit

// MARK: - Live Map View (UIKit Wrapper)

/// UIViewRepresentable wrapping MKMapView for custom annotations,
/// overlays, and performance control.

struct LiveMapView: UIViewRepresentable {
    @ObservedObject var viewModel: LiveMapViewModel

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .followWithHeading
        mapView.overrideUserInterfaceStyle = .dark
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        mapView.mapType = .mutedStandard

        // Gestures
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.5
        mapView.addGestureRecognizer(longPress)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.updateAnnotations(mapView: mapView, viewModel: viewModel)
        context.coordinator.updateOverlays(mapView: mapView, viewModel: viewModel)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        let viewModel: LiveMapViewModel

        init(viewModel: LiveMapViewModel) {
            self.viewModel = viewModel
        }

        // MARK: Annotations

        func updateAnnotations(mapView: MKMapView, viewModel: LiveMapViewModel) {
            let currentAnnotations = Set(mapView.annotations.compactMap { $0 as? RiderAnnotation })
            let newAnnotations = Set(viewModel.riderAnnotations)

            // Remove old
            for ann in currentAnnotations where !newAnnotations.contains(ann) {
                mapView.removeAnnotation(ann)
            }

            // Add new / update positions
            for ann in newAnnotations {
                if let existing = currentAnnotations.first(where: { $0.id == ann.id }) {
                    // Animate position update
                    UIView.animate(withDuration: 0.5) {
                        existing.coordinate = ann.coordinate
                    }
                    existing.update(from: ann)
                } else {
                    mapView.addAnnotation(ann)
                }
            }

            // Hazard annotations
            let currentHazards = Set(mapView.annotations.compactMap { $0 as? HazardAnnotation })
            let newHazards = Set(viewModel.hazardAnnotations)

            for ann in currentHazards where !newHazards.contains(ann) {
                mapView.removeAnnotation(ann)
            }
            for ann in newHazards where !currentHazards.contains(ann) {
                mapView.addAnnotation(ann)
            }
        }

        func updateOverlays(mapView: MKMapView, viewModel: LiveMapViewModel) {
            // Remove old route overlay
            mapView.removeOverlays(mapView.overlays)

            // Add route polyline
            if let route = viewModel.routePolyline {
                mapView.addOverlay(route)
            }
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case let riderAnn as RiderAnnotation:
                return RiderAnnotationView.create(for: riderAnn, in: mapView)

            case let hazardAnn as HazardAnnotation:
                return HazardAnnotationView.create(for: hazardAnn, in: mapView)

            default:
                return nil  // User location (blue dot)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemPurple
                renderer.lineWidth = 3
                renderer.lineCap = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        // MARK: Gestures

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            guard let mapView = gesture.view as? MKMapView else { return }

            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            viewModel.onMapLongPress?(coordinate)
        }
    }
}

// MARK: - Rider Annotation

final class RiderAnnotation: NSObject, MKAnnotation {
    let id: String
    let riderId: String
    let riderName: String
    let role: RideRole
    let speed: Double
    let isMoving: Bool
    let isOnline: Bool

    @objc dynamic var coordinate: CLLocationCoordinate2D
    var heading: Double

    var title: String? { riderName }
    var subtitle: String? {
        let moving = isMoving ? "\(Int(speed)) km/h" : "Parado"
        let status = isOnline ? moving : "Offline"
        return "\(role.displayName) • \(status)"
    }

    init(participant: RideParticipant) {
        self.id = participant.riderId
        self.riderId = participant.riderId
        self.riderName = participant.name
        self.role = participant.role
        self.speed = participant.speed
        self.isMoving = participant.isMoving
        self.isOnline = participant.isConnected
        self.coordinate = participant.coordinate
        self.heading = participant.heading
    }

    func update(from other: RiderAnnotation) {
        self.heading = other.heading
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? RiderAnnotation else { return false }
        return id == other.id
    }

    override var hash: Int { id.hashValue }

    // Hashable conformance via Equatable
    static func == (lhs: RiderAnnotation, rhs: RiderAnnotation) -> Bool {
        lhs.id == rhs.id
    }
}

extension RiderAnnotation {
    override var hashValue: Int { id.hashValue }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Rider Annotation View

final class RiderAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "RiderAnnotation"

    static func create(for annotation: RiderAnnotation, in mapView: MKMapView) -> MKAnnotationView {
        if let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier) as? RiderAnnotationView {
            view.annotation = annotation
            view.configure(for: annotation)
            return view
        }

        let view = RiderAnnotationView(annotation: annotation, reuseIdentifier: reuseIdentifier)
        view.configure(for: annotation)
        return view
    }

    func configure(for rider: RiderAnnotation) {
        canShowCallout = true

        // Size based on role
        let size: CGFloat = rider.role == .leader ? 44 : 36

        // Color based on role
        let color: UIColor = {
            if !rider.isOnline { return .systemGray }
            switch rider.role {
            case .leader: return .systemOrange
            case .rider: return .systemBlue
            case .sweeper: return .systemYellow
            }
        }()

        // Create pin image
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        image = renderer.image { ctx in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)

            // Circle background
            color.setFill()
            let path = UIBezierPath(ovalIn: rect)
            path.fill()

            // White border
            UIColor.white.setStroke()
            let borderPath = UIBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
            borderPath.lineWidth = 2
            borderPath.stroke()

            // Initials
            let initials = rider.riderName.components(separatedBy: " ")
                .prefix(2).compactMap { $0.first }.map { String($0) }.joined().uppercased()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size * 0.35, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let textSize = initials.size(withAttributes: attrs)
            let textRect = CGRect(
                x: (size - textSize.width) / 2,
                y: (size - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            initials.draw(in: textRect, withAttributes: attrs)
        }

        // Rotate to heading
        transform = CGAffineTransform(rotationAngle: CGFloat(rider.heading * .pi / 180))
    }
}

// MARK: - Hazard Annotation

final class HazardAnnotation: NSObject, MKAnnotation {
    let id: String
    let hazardType: HazardType
    let reportedBy: String
    let confidence: Int

    @objc dynamic var coordinate: CLLocationCoordinate2D

    var title: String? { hazardType.displayName }
    var subtitle: String? { "por \(reportedBy) • \(confidence) confirmações" }

    init(alert: HazardAlert) {
        self.id = alert.id
        self.hazardType = alert.type
        self.reportedBy = alert.reportedBy
        self.confidence = alert.confidence
        self.coordinate = alert.coordinate
    }

    override var hash: Int { id.hashValue }
    static func == (lhs: HazardAnnotation, rhs: HazardAnnotation) -> Bool {
        lhs.id == rhs.id
    }
}

func == (lhs: HazardAnnotation, rhs: HazardAnnotation) -> Bool {
    lhs.id == rhs.id
}

// MARK: - Hazard Annotation View

final class HazardAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "HazardAnnotation"

    static func create(for annotation: HazardAnnotation, in mapView: MKMapView) -> MKAnnotationView {
        if let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier) as? HazardAnnotationView {
            view.annotation = annotation
            view.configure(for: annotation)
            return view
        }

        let view = HazardAnnotationView(annotation: annotation, reuseIdentifier: reuseIdentifier)
        view.configure(for: annotation)
        return view
    }

    func configure(for hazard: HazardAnnotation) {
        canShowCallout = true

        let size: CGFloat = 32
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .semibold)

        let iconName: String = {
            switch hazard.hazardType {
            case .radar: return "antenna.radiowaves.left.and.right"
            case .pothole: return "circle.dotted"
            case .police: return "shield.righthalf.filled"
            case .oil: return "drop"
            case .animal: return "pawprint"
            case .gravel: return "circle.grid.3x3"
            case .accident: return "exclamationmark.triangle"
            case .other: return "exclamationmark.circle"
            }
        }()

        image = UIImage(systemName: iconName, withConfiguration: config)?
            .withTintColor(.systemRed, renderingMode: .alwaysOriginal)

        // Add background circle
        let bgSize = size + 12
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: bgSize, height: bgSize))
        let bgImage = renderer.image { ctx in
            UIColor.black.withAlphaComponent(0.7).setFill()
            let rect = CGRect(x: 0, y: 0, width: bgSize, height: bgSize)
            UIBezierPath(ovalIn: rect).fill()
        }

        // Composite
        let compositeRenderer = UIGraphicsImageRenderer(size: CGSize(width: bgSize, height: bgSize))
        image = compositeRenderer.image { ctx in
            bgImage.draw(at: .zero)
            image?.draw(at: CGPoint(x: 6, y: 6))
        }
    }
}
