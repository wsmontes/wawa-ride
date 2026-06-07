import SwiftUI
import AVFoundation
import CoreLocation
import MapKit

// MARK: - App Entry Point

@main
struct WAWARideApp: App {
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear { setupApp() }
                .preferredColorScheme(.dark)
                .onOpenURL { handleOpenURL($0) }
        }
    }

    private func setupApp() {
        VoiceAssistant.shared.setupAudioSession()
        ConnectivityMonitor.shared.start()
        LocationService.shared.requestPermission()
    }

    private func handleOpenURL(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ext == "gpx" || ext == "kml" else { return }
        if let route = RouteService.shared.importGPX(from: url) {
            VoiceAssistant.shared.speak(VoiceAssistant.routeImported(name: route.name, waypoints: route.waypoints.count))
        }
    }
}

// MARK: - Content View (Root — TabView)

struct ContentView: View {
    @StateObject private var appState = AppState.shared
    @State private var selectedTab = 0
    @State private var showCreateRide = false
    @State private var showOnboarding = !LocalStore.shared.profileExists()

    var body: some View {
        ZStack {
            if appState.currentRideId != nil {
                // In a ride — fullscreen map only (no tabs)
                UnifiedMapView(isInRide: true)
            } else {
                // Idle — TabView with map + library tabs
                TabView(selection: $selectedTab) {
                    UnifiedMapView(isInRide: false)
                        .tabItem { Label("Mapa", systemImage: "map") }
                        .tag(0)

                    RoutesLibraryView()
                        .tabItem { Label("Rotas", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }
                        .tag(1)

                    RidesListView(showCreateRide: $showCreateRide)
                        .tabItem { Label("Passeios", systemImage: "motorcycle") }
                        .tag(2)

                    ProfileTabView()
                        .tabItem { Label("Perfil", systemImage: "person.circle") }
                        .tag(3)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .rideEnded)) { _ in
            withAnimation {
                appState.currentRideId = nil
                appState.currentRideName = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .startSoloNavigation)) { notif in
            if appState.currentRideId == nil {
                appState.currentRideId = "solo-\(UUID().uuidString.prefix(8))"
                appState.currentRideName = "Navegação"
            }
            if let route = notif.object as? MKRoute {
                appState.pendingNavigationRoute = route
            }
        }
        .sheet(isPresented: $showOnboarding) {
            QuickOnboardingView(isPresented: $showOnboarding)
        }
        .sheet(isPresented: $showCreateRide) {
            CreateRideView()
        }
    }
}

// MARK: - Quick Onboarding (non-blocking)

struct QuickOnboardingView: View {
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var defaultRole: RideRole = .rider

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "motorcycle")
                    .font(.system(size: 64))
                    .foregroundColor(.orange)

                Text("Bem-vindo ao\nWAWA Ride")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text("Configure rapidamente para começar")
                    .foregroundColor(.secondary)

                VStack(spacing: 16) {
                    TextField("Seu nome ou apelido", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .padding(.horizontal)

                    Picker("Você é:", selection: $defaultRole) {
                        Text("🏍️ Líder (cria passeios)").tag(RideRole.leader)
                        Text("🏍️ Rider (entra nos passeios)").tag(RideRole.rider)
                        Text("🛡️ Varredor (último da fila)").tag(RideRole.sweeper)
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal)
                }

                Button {
                    saveAndDismiss()
                } label: {
                    Text(name.count >= 2 ? "COMEÇAR" : "PULAR")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(name.count >= 2 ? Color.orange : Color.gray)
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                Spacer()
            }
        }
    }

    private func saveAndDismiss() {
        if name.count >= 2 {
            let profile = RiderProfile(name: name, defaultRole: defaultRole)
            LocalStore.shared.saveProfile(profile)
        }
        isPresented = false
    }
}

// MARK: - Profile Tab (non-blocking)

struct ProfileTabView: View {
    @StateObject private var viewModel = ProfileViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Piloto") {
                    HStack {
                        Spacer()
                        Button {
                            viewModel.showPhotoPicker = true
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.orange.opacity(0.2))
                                    .frame(width: 80, height: 80)

                                Text(viewModel.initials)
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.orange)
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)

                    TextField("Nome ou apelido", text: $viewModel.name)
                    TextField("Moto (opcional)", text: $viewModel.bikeModel)
                }

                Section("Função padrão") {
                    Picker("Função", selection: $viewModel.defaultRole) {
                        ForEach(RideRole.allCases, id: \.self) { role in
                            Text(role.displayName).tag(role)
                        }
                    }
                }

                Section {
                    Button("Salvar alterações") {
                        viewModel.save()
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.orange)
                    .disabled(!viewModel.canSave)
                }
            }
            .navigationTitle("Perfil")
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let rideEnded = Notification.Name("rideEnded")
}
