import SwiftUI

// MARK: - Create Ride View (Dedicated Screen)

struct CreateRideView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CreateRideViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Nome do passeio") {
                    TextField("Ex: Serra do Rio do Rastro", text: $viewModel.rideName)
                        .submitLabel(.done)
                        .accessibilityLabel("Nome do passeio")
                        .accessibilityHint("Dê um nome para o passeio que os riders próximos verão")
                }

                Section("Rota (opcional)") {
                    Picker("Rota", selection: $viewModel.routeOption) {
                        Text("Sem rota (modo livre)").tag(RouteOption.none)
                        Text("Selecionar rota salva").tag(RouteOption.saved)
                        Text("Criar rota no mapa").tag(RouteOption.createNew)
                    }
                    .pickerStyle(.menu)

                    if viewModel.routeOption == .saved {
                        if viewModel.savedRoutes.isEmpty {
                            Text("Nenhuma rota salva. Crie uma na aba Rotas.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Picker("Rota salva", selection: $viewModel.selectedRouteId) {
                                ForEach(viewModel.savedRoutes, id: \.id) { route in
                                    Text(route.name).tag(route.id as String?)
                                }
                            }
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Seu iPhone vai anunciar o passeio via Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
                        Label("Riders próximos (até ~50m) veem e entram", systemImage: "person.2")
                        Label("Funciona sem internet — mesh P2P", systemImage: "wifi.slash")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                } header: {
                    Text("Como funciona")
                }
            }
            .navigationTitle("Criar Passeio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Criar") {
                        viewModel.createRide()
                        dismiss()
                    }
                    .disabled(viewModel.rideName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

enum RouteOption: String, CaseIterable {
    case none = "Sem rota"
    case saved = "Rota salva"
    case createNew = "Criar nova"
}

@MainActor
final class CreateRideViewModel: ObservableObject {
    @Published var rideName = ""
    @Published var routeOption: RouteOption = .none
    @Published var selectedRouteId: String?
    @Published var savedRoutes: [Route] = []

    init() {
        savedRoutes = LocalStore.shared.loadAllRoutes()
    }

    func createRide() {
        let profile = LocalStore.shared.loadProfile()
        let leaderName = profile?.name ?? "Líder"
        let leaderId = profile?.id ?? ""

        let rideId = UUID().uuidString
        let rideCode = generateRideCode()
        AppState.shared.currentRideId = rideId
        AppState.shared.currentRideName = rideName
        AppState.shared.currentRideCode = rideCode
        AppState.shared.rideStartedAt = Date()

        // Start advertising via BLE with confirmation code
        MeshService.shared.startAdvertising(
            rideId: rideId,
            rideName: rideName,
            leaderName: leaderName,
            riderCount: 1,
            roomCount: 2,
            rideCode: rideCode
        )

        // Start GPS tracking
        LocationService.shared.startTracking()

        // Create default rooms
        RoomService.shared.createDefaultRooms(rideId: rideId)

        // Save ride locally
        let ride = Ride(id: rideId, name: rideName, leaderId: leaderId, leaderName: leaderName)
        try? LocalStore.shared.saveRide(ride)

        // Load route if selected
        if routeOption == .saved, let routeId = selectedRouteId {
            let routes = LocalStore.shared.loadAllRoutes()
            if let route = routes.first(where: { $0.id == routeId }) {
                RouteService.shared.setActiveRoute(route)
            }
        }

        Logger.shared.ride("Ride created: '\(rideName)' code=\(rideCode) leader=\(leaderName)")
    }

    /// Generate a 4-character alphanumeric confirmation code
    private func generateRideCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // No I,O,0,1 to avoid confusion
        return String((0..<4).map { _ in chars.randomElement()! })
    }
}
