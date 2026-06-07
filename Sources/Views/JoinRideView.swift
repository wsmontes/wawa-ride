import SwiftUI

// MARK: - Join Ride View

struct JoinRideView: View {
    @StateObject private var viewModel = JoinRideViewModel()
    @State private var showCreateRide = false
    @State private var newRideName = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "motorcycle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)

                    Text("WAWA Ride")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
                .padding(.top, 32)

                // Status
                if !viewModel.discoveredRides.isEmpty {
                    // Found rides
                    VStack(alignment: .leading, spacing: 12) {
                        Text("🏍️ Passeios próximos")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(viewModel.discoveredRides) { ride in
                            DiscoveredRideCard(ride: ride) {
                                viewModel.joinRide(ride)
                            }
                        }
                    }
                    .padding(.horizontal)
                } else {
                    // Searching
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)

                        Text("Procurando passeios próximos...")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        if let error = viewModel.bluetoothError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.vertical, 40)
                }

                Divider()
                    .padding(.horizontal)

                Text("— OU —")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Create Ride button
                Button {
                    showCreateRide = true
                } label: {
                    Label("CRIAR PASSEIO", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.orange)
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                Spacer()
            }
            .alert("Criar Passeio", isPresented: $showCreateRide) {
                TextField("Nome do passeio", text: $newRideName)
                Button("Cancelar", role: .cancel) {}
                Button("Criar") {
                    viewModel.createRide(name: newRideName)
                }
                .disabled(newRideName.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("Dê um nome pro passeio. Os riders próximos vão ver este nome.")
            }
            .onAppear {
                viewModel.startBrowsing()
            }
            .onDisappear {
                viewModel.stopBrowsing()
            }
        }
    }
}

// MARK: - Discovered Ride Card

struct DiscoveredRideCard: View {
    let ride: MeshService.DiscoveredRide
    let onJoin: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(ride.rideName)
                    .font(.headline)

                Text("Líder: \(ride.leaderName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    Label("\(ride.riderCount) riders", systemImage: "person.2")
                    if ride.roomCount > 1 {
                        Label("\(ride.roomCount) salas", systemImage: "message")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onJoin) {
                Text("ENTRAR")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.green)
                    .cornerRadius(10)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Join Ride ViewModel

@MainActor
final class JoinRideViewModel: ObservableObject {
    @Published var discoveredRides: [MeshService.DiscoveredRide] = []
    @Published var bluetoothError: String?
    @Published var showLiveMap = false

    private let mesh = MeshService.shared
    private let locationService = LocationService.shared

    func startBrowsing() {
        // Check permissions
        if locationService.authorizationStatus == .denied || locationService.authorizationStatus == .restricted {
            bluetoothError = "Localização necessária. Autorize nos Ajustes."
            return
        }

        mesh.startBrowsing()
        bindMeshUpdates()
    }

    func stopBrowsing() {
        mesh.stopBrowsing()
    }

    private func bindMeshUpdates() {
        // Observe discovered rides
        Task {
            for await rides in mesh.$discoveredRides.values {
                await MainActor.run {
                    self.discoveredRides = rides
                }
            }
        }
    }

    func joinRide(_ discovered: MeshService.DiscoveredRide) {
        mesh.invitePeer(discovered.peerID)

        // Set app state
        AppState.shared.currentRideId = discovered.id
        AppState.shared.currentRideName = discovered.rideName

        // Navigate to live map
        showLiveMap = true
    }

    func createRide(name: String) {
        let profile = LocalStore.shared.loadProfile()
        let leaderName = profile?.name ?? "Líder"

        let rideId = UUID().uuidString
        AppState.shared.currentRideId = rideId
        AppState.shared.currentRideName = name

        // Start advertising
        mesh.startAdvertising(
            rideId: rideId,
            rideName: name,
            leaderName: leaderName,
            riderCount: 1,
            roomCount: 2  // Geral + Alertas
        )

        // Start tracking
        locationService.startTracking()

        // Create default rooms
        RoomService.shared.createDefaultRooms(rideId: rideId)

        // Create ride
        let ride = Ride(id: rideId, name: name, leaderId: profile?.id ?? "", leaderName: leaderName)
        try? LocalStore.shared.saveRide(ride)

        // Navigate to live map
        showLiveMap = true
    }
}
