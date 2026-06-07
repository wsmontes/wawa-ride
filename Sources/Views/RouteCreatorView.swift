import SwiftUI
import MapKit

// MARK: - Helpers

private func routeName(_ name: String, index: Int) -> String {
    name.isEmpty ? "Rota \(index + 1)" : name
}

private func routeInfo(_ route: MKRoute) -> String {
    let km = String(format: "%.1f", route.distance / 1000)
    let minutes = Int(route.expectedTravelTime / 60)
    let timeStr = minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)min" : "\(minutes) min"
    return "\(km) km • \(timeStr)"
}

private func routeAdvisory(_ route: MKRoute) -> String {
    "Transporte: \(route.transportType == .automobile ? "Carro/Moto" : "A pé")"
}

// MARK: - Route Creator View 2.0

struct RouteCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = RouteCreatorViewModel()
    @State private var routeName = ""
    @State private var showNamePrompt = false
    @State private var showAlternatives = false
    @State private var showWaypointEditor = false
    @State private var editingWaypoint: RouteWaypoint?
    @State private var editName = ""
    @State private var editIsStop = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Map
                RouteCreatorMapView(viewModel: viewModel)
                    .ignoresSafeArea(.all)

                VStack(spacing: 0) {
                    // Search bar
                    SearchBarView(
                        searchText: $viewModel.searchQuery,
                        completions: viewModel.completions,
                        isSearching: viewModel.isSearching,
                        mapRegion: nil,
                        onSelectCompletion: { completion in
                            viewModel.selectSearchCompletion(completion)
                        },
                        onSubmit: {
                            viewModel.searchAddress()
                        }
                    )
                    .padding(.top, 48)

                    Spacer()

                    // Bottom controls
                    VStack(spacing: 8) {
                        // Route info
                        if let route = viewModel.previewRoute {
                            HStack {
                                Label(
                                    "\(String(format: "%.1f", route.distance / 1000)) km • \(formatTime(route.expectedTravelTime))",
                                    systemImage: "car"
                                )
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)

                                if !viewModel.alternateRoutes.isEmpty {
                                    Button("Alternativas (\(viewModel.alternateRoutes.count + 1))") {
                                        showAlternatives = true
                                    }
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(8)
                                }
                            }
                        }

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

                            Button {
                                showWaypointEditor = true
                            } label: {
                                Label("Editar", systemImage: "pencil")
                                    .font(.subheadline)
                                    .padding(12)
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(8)
                            }
                            .disabled(viewModel.waypoints.isEmpty)

                            Spacer()

                            Button("Salvar") {
                                if viewModel.waypoints.count >= 2 {
                                    showNamePrompt = true
                                }
                            }
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .padding(12)
                            .background(viewModel.waypoints.count >= 2 ? Color.orange : Color.gray)
                            .cornerRadius(8)
                            .disabled(viewModel.waypoints.count < 2)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 32)
                    }
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
            .sheet(isPresented: $showAlternatives) {
                RouteAlternativesView(
                    routes: [viewModel.previewRoute].compactMap { $0 } + viewModel.alternateRoutes,
                    selectedIndex: $viewModel.selectedRouteIndex,
                    onSelect: { index in
                        viewModel.selectAlternative(at: index)
                        showAlternatives = false
                    }
                )
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showWaypointEditor) {
                WaypointEditorView(
                    waypoints: $viewModel.waypoints,
                    onDelete: { index in viewModel.deleteWaypoint(at: index) },
                    onReorder: { from, to in viewModel.moveWaypoint(from: from, to: to) },
                    onEdit: { index in
                        editingWaypoint = viewModel.waypoints[index]
                        editName = editingWaypoint?.name ?? "Ponto \(index + 1)"
                        editIsStop = editingWaypoint?.isStop ?? false
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $editingWaypoint) { wp in
                NavigationStack {
                    Form {
                        Section("Nome") {
                            TextField("Nome do ponto", text: $editName)
                        }
                        Section("Tipo") {
                            Toggle("Parada (posto, descanso)", isOn: $editIsStop)
                        }
                    }
                    .navigationTitle("Editar Ponto")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancelar") { editingWaypoint = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Salvar") {
                                viewModel.editWaypoint(wp, name: editName, isStop: editIsStop)
                                editingWaypoint = nil
                            }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)min"
        }
        return "\(minutes) min"
    }
}

// MARK: - Route Alternatives View

struct RouteAlternativesView: View {
    let routes: [MKRoute]
    @Binding var selectedIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        NavigationStack {
            List(Array(routes.enumerated()), id: \.offset) { index, route in
                Button {
                    onSelect(index)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(routeName(route.name, index: index))
                                .font(.headline)

                            Text(routeInfo(route))
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text(routeAdvisory(route))
                                .font(.caption)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if index == selectedIndex {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.orange)
                                .font(.title2)
                        }
                    }
                }
                .listRowBackground(index == selectedIndex ? Color.orange.opacity(0.1) : Color.clear)
            }
            .navigationTitle("Rotas alternativas")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)min"
        }
        return "\(minutes) min"
    }
}

// MARK: - Route Creator Map

struct RouteCreatorMapView: UIViewRepresentable {
    @ObservedObject var viewModel: RouteCreatorViewModel

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsCompass = true
        map.showsScale = true
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
        context.coordinator.updateAnnotations(mapView: mapView, viewModel: viewModel)
        context.coordinator.updateOverlays(mapView: mapView, viewModel: viewModel)
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

    func updateAnnotations(mapView: MKMapView, viewModel: RouteCreatorViewModel) {
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })

        for (index, wp) in viewModel.waypoints.enumerated() {
            let ann = MKPointAnnotation()
            ann.coordinate = wp.coordinate
            ann.title = wp.name ?? "Ponto \(index + 1)"
            ann.subtitle = wp.isStop ? "Parada" : nil
            mapView.addAnnotation(ann)
        }
    }

    func updateOverlays(mapView: MKMapView, viewModel: RouteCreatorViewModel) {
        mapView.removeOverlays(mapView.overlays)

        // Preview route polyline (from MKDirections)
        if let polyline = viewModel.previewPolyline {
            mapView.addOverlay(polyline)
        }
    }

    // MARK: - MKMapViewDelegate

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor.systemBlue
            renderer.lineWidth = 4
            renderer.lineCap = .round
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard !(annotation is MKUserLocation) else { return nil }

        let view = mapView.dequeueReusableAnnotationView(withIdentifier: "waypoint") as? MKMarkerAnnotationView
            ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "waypoint")

        view.canShowCallout = true
        view.markerTintColor = .systemOrange
        return view
    }
}

// MARK: - Route Creator ViewModel

@MainActor
final class RouteCreatorViewModel: ObservableObject {
    @Published var waypoints: [RouteWaypoint] = []
    @Published var previewRoute: MKRoute?
    @Published var previewPolyline: MKPolyline?
    @Published var alternateRoutes: [MKRoute] = []
    @Published var selectedRouteIndex = 0

    // Search
    @Published var searchQuery = ""
    @Published var completions: [MKLocalSearchCompletion] = []
    @Published var isSearching = false

    private let searchService = SearchService.shared
    private let directionsService = DirectionsService.shared

    func addWaypoint(at coordinate: CLLocationCoordinate2D) {
        let wp = RouteWaypoint(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            order: waypoints.count
        )
        waypoints.append(wp)
        updateRoutePreview()
    }

    func undoLastWaypoint() {
        guard !waypoints.isEmpty else { return }
        waypoints.removeLast()
        reindexWaypoints()
        if waypoints.count >= 2 { updateRoutePreview() }
        else { previewRoute = nil; previewPolyline = nil }
    }

    func deleteWaypoint(at index: Int) {
        guard index < waypoints.count else { return }
        waypoints.remove(at: index)
        reindexWaypoints()
        if waypoints.count >= 2 { updateRoutePreview() }
        else { previewRoute = nil; previewPolyline = nil }
    }

    func moveWaypoint(from source: Int, to destination: Int) {
        guard source < waypoints.count, destination < waypoints.count else { return }
        let item = waypoints.remove(at: source)
        waypoints.insert(item, at: destination)
        reindexWaypoints()
        if waypoints.count >= 2 { updateRoutePreview() }
    }

    func editWaypoint(_ wp: RouteWaypoint, name: String, isStop: Bool) {
        guard let index = waypoints.firstIndex(where: { $0.id == wp.id }) else { return }
        waypoints[index].name = name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : name.trimmingCharacters(in: .whitespaces)
        waypoints[index].isStop = isStop
        waypoints[index].type = isStop ? .stop : .waypoint
    }

    private func reindexWaypoints() {
        for i in waypoints.indices { waypoints[i].order = i }
    }

    // MARK: - Route Preview via MKDirections

    private func updateRoutePreview() {
        guard waypoints.count >= 2 else { return }

        let coords = waypoints.map { $0.coordinate }

        Task {
            do {
                let routes = try await directionsService.calculateRouteWithWaypoints(
                    waypoints: coords,
                    alternateRoutes: waypoints.count == 2
                )

                if let first = routes.first {
                    previewRoute = first
                    previewPolyline = first.polyline

                    // Separate alternates from main
                    if routes.count > 1 {
                        alternateRoutes = Array(routes.dropFirst())
                    }
                }
            } catch {
                print("📍 Route preview error: \(error)")
            }
        }
    }

    func selectAlternative(at index: Int) {
        let allRoutes = [previewRoute].compactMap { $0 } + alternateRoutes
        guard index < allRoutes.count else { return }
        selectedRouteIndex = index
        previewPolyline = allRoutes[index].polyline
    }

    // MARK: - Search

    func searchAddress() {
        guard !searchQuery.isEmpty else { return }
        isSearching = true

        Task {
            do {
                let results = try await searchService.search(query: searchQuery)
                if let first = results.first, let location = first.location {
                    addWaypoint(at: location.coordinate)
                }
            } catch {
                print("🔍 Search error: \(error)")
            }
            isSearching = false
            searchQuery = ""
        }
    }

    func selectSearchCompletion(_ completion: MKLocalSearchCompletion) {
        isSearching = true

        Task {
            do {
                let results = try await searchService.search(completion: completion)
                if let first = results.first, let location = first.location {
                    addWaypoint(at: location.coordinate)
                }
            } catch {
                print("🔍 Search error: \(error)")
            }
            isSearching = false
            searchQuery = ""
            searchService.clearCompletions()
        }
    }

    // MARK: - Save

    func saveRoute(name: String) {
        guard waypoints.count >= 2 else { return }
        _ = RouteService.shared.createDrawnRoute(name: name, waypoints: waypoints)
    }
}

// MARK: - MKMapItem Extension

extension MKMapItem {
    var location: CLLocation? {
        placemark.location
    }
}

// MARK: - Waypoint Editor View

struct WaypointEditorView: View {
    @Binding var waypoints: [RouteWaypoint]
    var onDelete: (Int) -> Void
    var onReorder: (Int, Int) -> Void
    var onEdit: (Int) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(waypoints.enumerated()), id: \.element.id) { index, wp in
                    HStack(spacing: 12) {
                        Image(systemName: wp.isStop ? "stop.circle" : "mappin")
                            .foregroundColor(wp.isStop ? .orange : .blue)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(wp.name ?? "Ponto \(index + 1)")
                                .font(.subheadline)
                            Text(wp.isStop ? "Parada" : "Passagem")
                                .font(.caption).foregroundColor(.secondary)
                        }

                        Spacer()

                        Button { onEdit(index) } label: {
                            Image(systemName: "pencil.circle").font(.title3)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { indexSet in
                    if let idx = indexSet.first { onDelete(idx) }
                }
                .onMove { from, to in
                    onReorder(from.first!, to)
                }
            }
            .navigationTitle("Editar Pontos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                EditButton()
            }
        }
    }
}
