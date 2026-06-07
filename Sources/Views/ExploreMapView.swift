import SwiftUI
import MapKit

// MARK: - Explore Map View

struct ExploreMapView: View {
    @Binding var selectedTab: Int
    @StateObject private var viewModel = ExploreMapViewModel()

    @State private var selectedPlace: PlaceCardItem?
    @State private var showPlaceCard = false
    @State private var showDirections = false
    @State private var directionsDestination: CLLocationCoordinate2D?
    @State private var directionsName = ""

    var body: some View {
        ZStack {
            ExploreMapUIKit(viewModel: viewModel, onPlaceSelected: { item in
                selectedPlace = item
                showPlaceCard = true
            }, onMapTap: {
                showPlaceCard = false
            })
            .ignoresSafeArea(.all)

            VStack(spacing: 0) {
                // Search bar
                SearchBarView(
                    searchText: $viewModel.searchQuery,
                    completions: viewModel.completions,
                    isSearching: viewModel.isSearching,
                    onSelectCompletion: { completion in
                        viewModel.selectSearchCompletion(completion) { item in
                            selectedPlace = item
                            showPlaceCard = true
                        }
                    },
                    onSubmit: {
                        viewModel.searchAddress { item in
                            selectedPlace = item
                            showPlaceCard = true
                        }
                    }
                )
                .padding(.top, 48)

                // BLE Ride banner
                if !viewModel.nearbyRides.isEmpty {
                    nearbyRidesBanner
                }

                Spacer()

                // Bottom quick actions (only when no sheet is open)
                if !showPlaceCard && !showDirections {
                    HStack(spacing: 16) {
                        Button {
                            selectedTab = 2
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                NotificationCenter.default.post(name: .showCreateRide, object: nil)
                            }
                        } label: {
                            Label("Criar Passeio", systemImage: "plus.circle.fill")
                                .font(.headline).foregroundColor(.white)
                                .padding(.horizontal, 20).padding(.vertical, 14)
                                .background(Color.orange).cornerRadius(28)
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .sheet(isPresented: $showPlaceCard) {
            if let place = selectedPlace {
                PlaceCardView(
                    item: place,
                    onDirections: {
                        showPlaceCard = false
                        directionsDestination = place.coordinate
                        directionsName = place.name
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            showDirections = true
                        }
                    },
                    onDismiss: { showPlaceCard = false }
                )
            }
        }
        .sheet(isPresented: $showDirections) {
            if let dest = directionsDestination, let source = LocationService.shared.currentLocation?.coordinate {
                DirectionsPreviewView(
                    source: source,
                    destination: dest,
                    destinationName: directionsName
                ) { route in
                    viewModel.startNavigation(with: route)
                }
            }
        }
        .onAppear { viewModel.startBrowsing() }
        .onDisappear { viewModel.stopBrowsing() }
    }

    // MARK: - Nearby Rides Banner

    var nearbyRidesBanner: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.nearbyRides) { ride in
                Button {
                    viewModel.joinRide(ride)
                } label: {
                    HStack {
                        Image(systemName: "motorcycle").font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ride.rideName).font(.subheadline).fontWeight(.semibold)
                            Text("Líder: \(ride.leaderName) • \(ride.riderCount) riders").font(.caption)
                        }
                        Spacer()
                        Text("ENTRAR")
                            .font(.caption).fontWeight(.bold).foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Color.green).cornerRadius(16)
                    }
                    .padding(12)
                    .background(Color(.systemGray6).opacity(0.95))
                    .cornerRadius(12).padding(.horizontal)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Explore Map UIKit Wrapper

struct ExploreMapUIKit: UIViewRepresentable {
    @ObservedObject var viewModel: ExploreMapViewModel
    var onPlaceSelected: (PlaceCardItem) -> Void
    var onMapTap: () -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.userTrackingMode = .follow
        map.showsCompass = true
        map.showsScale = true
        map.showsUserTrackingButton = true
        map.showsTraffic = true
        map.isPitchEnabled = true
        map.isRotateEnabled = true
        map.mapType = .mutedStandard
        map.overrideUserInterfaceStyle = .dark

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        map.addGestureRecognizer(longPress)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)

        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.updateAnnotations(map: map, viewModel: viewModel)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, onPlaceSelected: onPlaceSelected, onMapTap: onMapTap)
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        let viewModel: ExploreMapViewModel
        let onPlaceSelected: (PlaceCardItem) -> Void
        let onMapTap: () -> Void

        init(viewModel: ExploreMapViewModel, onPlaceSelected: @escaping (PlaceCardItem) -> Void, onMapTap: @escaping () -> Void) {
            self.viewModel = viewModel
            self.onPlaceSelected = onPlaceSelected
            self.onMapTap = onMapTap
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            guard let mapView = gesture.view as? MKMapView else { return }
            let coord = mapView.convert(gesture.location(in: mapView), toCoordinateFrom: mapView)
            viewModel.addDroppedPin(at: coord) { item in
                self.onPlaceSelected(item)
            }
        }

        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            // Check if tapped on an annotation
            let tappedAnnotations = mapView.annotations.filter { ann in
                if let view = mapView.view(for: ann) {
                    return view.frame.contains(point)
                }
                return false
            }
            if tappedAnnotations.isEmpty {
                onMapTap()
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        func updateAnnotations(map mapView: MKMapView, viewModel: ExploreMapViewModel) {
            let existing = Set(mapView.annotations.compactMap { $0 as? MKPointAnnotation }.map { $0.title ?? "" })
            let wanted = Set(viewModel.pins.map { $0.title })

            // Only remove if completely different set
            if existing != wanted {
                mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
                for pin in viewModel.pins {
                    let ann = MKPointAnnotation()
                    ann.coordinate = pin.coordinate
                    ann.title = pin.title
                    ann.subtitle = pin.subtitle
                    mapView.addAnnotation(ann)
                }
            }

            // Zoom to show all pins if new ones were added
            if !viewModel.pins.isEmpty && viewModel.shouldZoomToPins {
                mapView.showAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) }, animated: true)
                viewModel.shouldZoomToPins = false
            }
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            guard !(annotation is MKUserLocation) else { return }
            // Find the place item for this annotation
            if let pin = viewModel.pins.first(where: { $0.coordinate.latitude == annotation.coordinate.latitude && $0.coordinate.longitude == annotation.coordinate.longitude }) {
                onPlaceSelected(PlaceCardItem(coordinate: pin.coordinate, name: pin.title, address: pin.subtitle))
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "pin") as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "pin")
            view.canShowCallout = false  // We handle selection with our own sheet
            view.markerTintColor = .systemOrange
            view.animatesWhenAdded = true
            return view
        }
    }
}

// MARK: - Explore Map ViewModel

@MainActor
final class ExploreMapViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var completions: [MKLocalSearchCompletion] = []
    @Published var isSearching = false
    @Published var nearbyRides: [MeshService.DiscoveredRide] = []
    @Published var pins: [ExplorePin] = []
    @Published var shouldZoomToPins = false

    private let searchService = SearchService.shared
    private let mesh = MeshService.shared

    struct ExplorePin: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
        let title: String
        let subtitle: String?
        let mapItem: MKMapItem?
    }

    func startBrowsing() { mesh.startBrowsing() }
    func stopBrowsing() { mesh.stopBrowsing() }

    // MARK: - Search

    func searchAddress(onResult: @escaping (PlaceCardItem) -> Void) {
        guard !searchQuery.isEmpty else { return }
        isSearching = true
        Task {
            do {
                let results = try await searchService.search(query: searchQuery)
                pins.removeAll()
                for item in results {
                    if let loc = item.location {
                        pins.append(ExplorePin(coordinate: loc.coordinate, title: item.name ?? "Resultado", subtitle: item.placemark.title, mapItem: item))
                    }
                }
                shouldZoomToPins = true
                if let first = results.first, let loc = first.location {
                    onResult(PlaceCardItem(mapItem: first, currentLocation: LocationService.shared.currentLocation))
                }
            } catch { print("🔍 Search error: \(error)") }
            isSearching = false
            searchQuery = ""
        }
    }

    func selectSearchCompletion(_ completion: MKLocalSearchCompletion, onResult: @escaping (PlaceCardItem) -> Void) {
        isSearching = true
        Task {
            do {
                let results = try await searchService.search(completion: completion)
                pins.removeAll()
                for item in results {
                    if let loc = item.location {
                        pins.append(ExplorePin(coordinate: loc.coordinate, title: item.name ?? completion.title, subtitle: completion.subtitle, mapItem: item))
                    }
                }
                shouldZoomToPins = true
                if let first = results.first, let loc = first.location {
                    onResult(PlaceCardItem(mapItem: first, currentLocation: LocationService.shared.currentLocation))
                }
            } catch { print("🔍 Search error: \(error)") }
            isSearching = false
            searchQuery = ""
            searchService.clearCompletions()
        }
    }

    func addDroppedPin(at coordinate: CLLocationCoordinate2D, onResult: @escaping (PlaceCardItem) -> Void) {
        pins.removeAll()
        let pin = ExplorePin(coordinate: coordinate, title: "Pino marcado", subtitle: "Toque para ver opções", mapItem: nil)
        pins.append(pin)
        shouldZoomToPins = false
        onResult(PlaceCardItem(coordinate: coordinate, name: "Pino marcado", address: "\(String(format: "%.5f", coordinate.latitude)), \(String(format: "%.5f", coordinate.longitude))"))
    }

    func joinRide(_ ride: MeshService.DiscoveredRide) {
        mesh.invitePeer(ride.peerID)
        AppState.shared.currentRideId = ride.id
        AppState.shared.currentRideName = ride.rideName
    }

    // MARK: - Navigation

    func startNavigation(with route: MKRoute) {
        // Navigation is started from RideActiveView
        // Store the route and switch to ride mode
        AppState.shared.pendingNavigationRoute = route
        NotificationCenter.default.post(name: .startSoloNavigation, object: route)
    }
}

extension Notification.Name {
    static let showCreateRide = Notification.Name("showCreateRide")
    static let startSoloNavigation = Notification.Name("startSoloNavigation")
}
