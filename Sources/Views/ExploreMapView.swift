import SwiftUI
import MapKit

// MARK: - Explore Map View (Standalone — works without an active ride)

/// Free map accessible at all times. Search, explore, plan routes.
/// BLE ride discovery is a non-blocking banner, not the primary UI.

struct ExploreMapView: View {
    @Binding var selectedTab: Int
    @StateObject private var viewModel = ExploreMapViewModel()

    var body: some View {
        ZStack {
            // Map
            ExploreMapUIKit(viewModel: viewModel)
                .ignoresSafeArea(.all)

            // Overlays
            VStack(spacing: 0) {
                // Top: Search bar
                SearchBarView(
                    searchText: $viewModel.searchQuery,
                    completions: viewModel.completions,
                    isSearching: viewModel.isSearching,
                    onSelectCompletion: { completion in
                        viewModel.selectSearchCompletion(completion)
                    },
                    onSubmit: {
                        viewModel.searchAddress()
                    }
                )
                .padding(.top, 48)

                // BLE Ride banner (only if rides detected)
                if !viewModel.nearbyRides.isEmpty {
                    nearbyRidesBanner
                }

                Spacer()

                // Bottom: Quick actions
                HStack(spacing: 16) {
                    // Create ride
                    Button {
                        selectedTab = 2  // Switch to Passeios tab
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            NotificationCenter.default.post(name: .showCreateRide, object: nil)
                        }
                    } label: {
                        Label("Criar Passeio", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(Color.orange)
                            .cornerRadius(28)
                    }

                    // Plan route
                    Button {
                        selectedTab = 1  // Switch to routes tab
                    } label: {
                        Label("Planejar Rota", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(28)
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            viewModel.startBrowsing()
        }
        .onDisappear {
            viewModel.stopBrowsing()
        }
    }

    // MARK: - Nearby Rides Banner

    var nearbyRidesBanner: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.nearbyRides) { ride in
                Button {
                    viewModel.joinRide(ride)
                } label: {
                    HStack {
                        Image(systemName: "motorcycle")
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(ride.rideName)
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Text("Líder: \(ride.leaderName) • \(ride.riderCount) riders")
                                .font(.caption)
                        }

                        Spacer()

                        Text("ENTRAR")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.green)
                            .cornerRadius(16)
                    }
                    .padding(12)
                    .background(Color(.systemGray6).opacity(0.95))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Explore Map UIKit Wrapper

struct ExploreMapUIKit: UIViewRepresentable {
    @ObservedObject var viewModel: ExploreMapViewModel

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

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.5
        map.addGestureRecognizer(longPress)

        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.updateAnnotations(map: map, viewModel: viewModel)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let viewModel: ExploreMapViewModel

        init(viewModel: ExploreMapViewModel) {
            self.viewModel = viewModel
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            guard let mapView = gesture.view as? MKMapView else { return }
            let coord = mapView.convert(gesture.location(in: mapView), toCoordinateFrom: mapView)
            viewModel.addDroppedPin(at: coord)
        }

        func updateAnnotations(map mapView: MKMapView, viewModel: ExploreMapViewModel) {
            mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
            for pin in viewModel.pins {
                let ann = MKPointAnnotation()
                ann.coordinate = pin.coordinate
                ann.title = pin.title
                ann.subtitle = pin.subtitle
                mapView.addAnnotation(ann)
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "pin") as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "pin")
            view.canShowCallout = true
            view.markerTintColor = .systemOrange
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

    private let searchService = SearchService.shared
    private let mesh = MeshService.shared

    struct ExplorePin: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
        let title: String
        let subtitle: String?
    }

    func startBrowsing() {
        mesh.startBrowsing()
    }

    func stopBrowsing() {
        mesh.stopBrowsing()
    }

    func searchAddress() {
        guard !searchQuery.isEmpty else { return }
        isSearching = true
        Task {
            do {
                let results = try await searchService.search(query: searchQuery)
                for item in results {
                    if let location = item.location {
                        pins.append(ExplorePin(
                            coordinate: location.coordinate,
                            title: item.name ?? "Resultado",
                            subtitle: item.placemark.title
                        ))
                    }
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
                for item in results {
                    if let location = item.location {
                        pins.append(ExplorePin(
                            coordinate: location.coordinate,
                            title: item.name ?? completion.title,
                            subtitle: completion.subtitle
                        ))
                    }
                }
            } catch {
                print("🔍 Search error: \(error)")
            }
            isSearching = false
            searchQuery = ""
            searchService.clearCompletions()
        }
    }

    func addDroppedPin(at coordinate: CLLocationCoordinate2D) {
        pins.append(ExplorePin(
            coordinate: coordinate,
            title: "Pino",
            subtitle: "\(String(format: "%.5f", coordinate.latitude)), \(String(format: "%.5f", coordinate.longitude))"
        ))
    }

    func joinRide(_ ride: MeshService.DiscoveredRide) {
        mesh.invitePeer(ride.peerID)
        AppState.shared.currentRideId = ride.id
        AppState.shared.currentRideName = ride.rideName
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showCreateRide = Notification.Name("showCreateRide")
}
