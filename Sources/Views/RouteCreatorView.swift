import SwiftUI
import MapKit

// MARK: - Route Creator View

struct RouteCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = RouteCreatorViewModel()
    @State private var routeName = ""
    @State private var showNamePrompt = false

    var body: some View {
        NavigationStack {
            ZStack {
                RouteCreatorMapView(viewModel: viewModel)
                    .ignoresSafeArea(.all)

                VStack {
                    // Top controls
                    HStack {
                        Button("Cancelar") {
                            dismiss()
                        }
                        .padding(12)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)

                        Spacer()

                        Text("\(viewModel.waypoints.count) pontos")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)

                        Spacer()

                        Button("Salvar") {
                            showNamePrompt = true
                        }
                        .padding(12)
                        .background(Color.orange)
                        .cornerRadius(8)
                        .disabled(viewModel.waypoints.count < 2)
                    }
                    .padding(.horizontal)
                    .padding(.top, 48)

                    Spacer()

                    // Bottom controls
                    HStack {
                        Button {
                            viewModel.undoLastWaypoint()
                        } label: {
                            Label("Desfazer", systemImage: "arrow.uturn.backward")
                                .font(.subheadline)
                                .padding(12)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)
                        }
                        .disabled(viewModel.waypoints.isEmpty)

                        Spacer()

                        Text("Long press no mapa para adicionar pontos")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
            .alert("Nome da Rota", isPresented: $showNamePrompt) {
                TextField("Nome", text: $routeName)
                Button("Salvar") {
                    viewModel.saveRoute(name: routeName)
                    dismiss()
                }
                Button("Cancelar", role: .cancel) {}
            }
        }
    }
}

// MARK: - Route Creator Map

struct RouteCreatorMapView: UIViewRepresentable {
    @ObservedObject var viewModel: RouteCreatorViewModel

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(RouteCreatorCoordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.5
        map.addGestureRecognizer(longPress)

        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update waypoint annotations
        let currentAnns = Set(mapView.annotations.compactMap { $0 as? MKPointAnnotation })
        let newAnns = viewModel.waypoints.map { wp -> MKPointAnnotation in
            let ann = MKPointAnnotation()
            ann.coordinate = wp.coordinate
            ann.title = wp.name ?? "Ponto \(wp.order + 1)"
            return ann
        }

        mapView.removeAnnotations(mapView.annotations)
        mapView.addAnnotations(newAnns)

        // Update polyline
        mapView.removeOverlays(mapView.overlays)
        if viewModel.previewLine != nil {
            let coords = viewModel.waypoints.map { $0.coordinate }
            if coords.count > 1 {
                let polyline = MKPolyline(coordinates: coords, count: coords.count)
                mapView.addOverlay(polyline)
            }
        }
    }

    func makeCoordinator() -> RouteCreatorCoordinator {
        RouteCreatorCoordinator(viewModel: viewModel)
    }
}

final class RouteCreatorCoordinator: NSObject, MKMapViewDelegate {
    let viewModel: RouteCreatorViewModel

    init(viewModel: RouteCreatorViewModel) {
        self.viewModel = viewModel
    }

    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        guard let mapView = gesture.view as? MKMapView else { return }

        let point = gesture.location(in: mapView)
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
        viewModel.addWaypoint(at: coordinate)
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor.systemOrange
            renderer.lineWidth = 3
            renderer.lineDashPattern = [6, 3]
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}

// MARK: - Route Creator ViewModel

@MainActor
final class RouteCreatorViewModel: ObservableObject {
    @Published var waypoints: [RouteWaypoint] = []
    @Published var previewLine: MKPolyline?

    func addWaypoint(at coordinate: CLLocationCoordinate2D) {
        let wp = RouteWaypoint(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            order: waypoints.count
        )
        waypoints.append(wp)

        if waypoints.count > 1 {
            let coords = waypoints.map { $0.coordinate }
            previewLine = MKPolyline(coordinates: coords, count: coords.count)
        }
    }

    func undoLastWaypoint() {
        guard !waypoints.isEmpty else { return }
        waypoints.removeLast()

        if waypoints.count > 1 {
            let coords = waypoints.map { $0.coordinate }
            previewLine = MKPolyline(coordinates: coords, count: coords.count)
        } else {
            previewLine = nil
        }
    }

    func saveRoute(name: String) {
        guard waypoints.count >= 2 else { return }
        _ = RouteService.shared.createDrawnRoute(name: name, waypoints: waypoints)
    }
}
