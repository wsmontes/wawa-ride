import SwiftUI
import AVFoundation
import CoreLocation
import MapKit
import PhotosUI

// MARK: - App Entry Point

@main
struct WAWARideApp: App {
    @StateObject private var appState = AppState.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear { setupApp() }
                .preferredColorScheme(.dark)
                .dynamicTypeSize(.xSmall ... .xxxLarge)  // Support all Dynamic Type sizes
                .onOpenURL { handleOpenURL($0) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                // Persist active ride ID so we can restore on relaunch
                if let rideId = appState.currentRideId {
                    UserDefaults.standard.set(rideId, forKey: "lastActiveRideId")
                    UserDefaults.standard.set(appState.currentRideName, forKey: "lastActiveRideName")
                    UserDefaults.standard.set(appState.currentRideCode, forKey: "lastActiveRideCode")
                    Logger.shared.ride("App backgrounded — ride '\(appState.currentRideName ?? "")' persisted")
                }
            case .active:
                // Restore ride if app was killed and relaunched
                if appState.currentRideId == nil,
                   let savedRideId = UserDefaults.standard.string(forKey: "lastActiveRideId"),
                   let savedRideName = UserDefaults.standard.string(forKey: "lastActiveRideName") {
                    appState.currentRideId = savedRideId
                    appState.currentRideName = savedRideName
                    appState.currentRideCode = UserDefaults.standard.string(forKey: "lastActiveRideCode")
                    Logger.shared.ride("App relaunched — restoring ride '\(savedRideName)'")
                    // Clear saved state since we restored it
                    UserDefaults.standard.removeObject(forKey: "lastActiveRideId")
                    UserDefaults.standard.removeObject(forKey: "lastActiveRideName")
                    UserDefaults.standard.removeObject(forKey: "lastActiveRideCode")
                }
            default:
                break
            }
        }
    }

    private func setupApp() {
        VoiceAssistant.shared.setupAudioSession()
        ConnectivityMonitor.shared.start()
        LocationService.shared.requestPermission()
    }

    private func handleOpenURL(_ url: URL) {
        // Handle geo: URIs (if feature flag enabled)
        if FeatureFlags.shared.geoURI, url.scheme == "geo", let coords = parseGeoURI(url) {
            NotificationCenter.default.post(name: .openGeoCoordinate, object: coords)
            return
        }
        // Handle GPX/KML files (KML only if feature flag enabled)
        let ext = url.pathExtension.lowercased()
        let allowedExts = FeatureFlags.shared.kmlImport ? ["gpx", "kml"] : ["gpx"]
        guard allowedExts.contains(ext) else { return }
        if let route = RouteService.shared.importGPX(from: url) {
            VoiceAssistant.shared.speak(VoiceAssistant.routeImported(name: route.name, waypoints: route.waypoints.count))
        }
    }

    private func parseGeoURI(_ url: URL) -> GeoCoordinate? {
        // geo:lat,lng or geo:0,0?q=lat,lng(label)
        guard url.scheme == "geo" else { return nil }
        let str = url.absoluteString.replacingOccurrences(of: "geo:", with: "")
        // Check query format: geo:0,0?q=lat,lng(label)
        if let queryRange = str.range(of: "?q=") {
            let query = String(str[queryRange.upperBound...])
            let parts = query.components(separatedBy: ",")
            if parts.count >= 2, let lat = Double(parts[0]), let lng = Double(parts[1]) {
                let label = parts.count >= 3 ? parts[2].replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "") : nil
                return GeoCoordinate(lat: lat, lng: lng, label: label)
            }
        }
        // Direct format: geo:lat,lng
        let parts = str.components(separatedBy: ",")
        if parts.count >= 2, let lat = Double(parts[0]), let lng = Double(parts[1]) {
            return GeoCoordinate(lat: lat, lng: lng, label: nil)
        }
        return nil
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

                // What to expect
                VStack(alignment: .leading, spacing: 8) {
                    Label("Abra o app perto de outros riders — eles aparecem aqui", systemImage: "antenna.radiowaves.left.and.right")
                    Label("Toque ENTRAR e já estão conectados, sem código", systemImage: "person.2.fill")
                    Label("Veja o grupo no mapa e fale via walkie-talkie", systemImage: "map.fill")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)

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
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section("Piloto") {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            if let photoData = viewModel.photoData, let uiImage = UIImage(data: photoData) {
                                Image(uiImage: uiImage)
                                    .resizable().scaledToFill()
                                    .frame(width: 80, height: 80).clipShape(Circle())
                                    .overlay(Circle().stroke(Color.orange, lineWidth: 3))
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(Color.orange.opacity(0.2))
                                        .frame(width: 80, height: 80)
                                    Text(viewModel.initials)
                                        .font(.title).fontWeight(.bold).foregroundColor(.orange)
                                }
                                .overlay(Circle().stroke(Color.orange, lineWidth: 3))
                            }
                        }
                        .onChange(of: selectedPhotoItem) { _, item in
                            Task {
                                if let data = try? await item?.loadTransferable(type: Data.self) {
                                    // Compress to max 200KB
                                    if let image = UIImage(data: data),
                                       let compressed = image.jpegData(compressionQuality: 0.5) {
                                        viewModel.photoData = compressed.prefix(200_000).count > 200_000
                                            ? image.jpegData(compressionQuality: 0.2) : compressed
                                    } else {
                                        viewModel.photoData = data
                                    }
                                    viewModel.save()
                                }
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

                if FeatureFlags.shared.showDiagnostics {
                    Section {
                        NavigationLink("Diagnóstico") {
                            DiagnosticView()
                        }
                    }
                }

                Section {
                    NavigationLink("Política de Privacidade") {
                        PrivacyPolicyView()
                    }
                    NavigationLink("Sobre o WAWA Ride") {
                        AboutView()
                    }
                }
            }
            .navigationTitle("Perfil")
        }
    }
}

// MARK: - Geo Coordinate

struct GeoCoordinate {
    let lat: Double
    let lng: Double
    let label: String?
}

// MARK: - Notification Names

extension Notification.Name {
    static let rideEnded = Notification.Name("rideEnded")
    static let openGeoCoordinate = Notification.Name("openGeoCoordinate")
}

// MARK: - Privacy Policy View

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Política de Privacidade")
                    .font(.title2).fontWeight(.bold)

                Text("Última atualização: Junho 2026")
                    .font(.caption).foregroundColor(.secondary)

                Text("O WAWA Ride foi construído com privacidade como princípio fundamental. Nós não temos servidores, não coletamos seus dados e não rastreamos você.")

                Group {
                    Text("Dados que NUNCA saem do seu iPhone")
                        .font(.headline)
                    Text("• Sua localização — processada exclusivamente no dispositivo\n• Seu nome, foto e perfil — armazenados apenas localmente\n• Suas rotas e histórico de passeios — no seu iPhone\n• Suas mensagens de voz — transmitidas apenas P2P, nunca armazenadas em servidores\n• Seus contatos — o app nunca acessa")

                    Text("O que é compartilhado (apenas com riders no seu grupo)")
                        .font(.headline)
                    Text("• Sua posição no mapa — visível apenas para riders conectados ao mesmo passeio\n• Seu nome/apelido — para identificação no grupo\n• Alertas de perigo que você marcar\n• Mensagens de voz que você enviar\n\nToda comunicação é direta entre dispositivos (P2P) via Bluetooth e WiFi Direct. Nada passa por servidores externos.")

                    Text("Permissões")
                        .font(.headline)
                    Text("• Localização: necessária para mostrar sua posição no mapa do grupo. Usada apenas durante o passeio.\n• Microfone: necessário para o walkie-talkie. Usado apenas quando você aperta FALAR.\n• Bluetooth: necessário para descobrir riders próximos e conectar o grupo.\n\nVocê pode revogar qualquer permissão nos Ajustes do iPhone a qualquer momento.")

                    Text("Sem anúncios, sem rastreamento")
                        .font(.headline)
                    Text("O WAWA Ride não contém anúncios, não usa frameworks de analytics, não integra SDKs de terceiros para rastreamento, e não monetiza seus dados de forma alguma.")

                    Text("Contato")
                        .font(.headline)
                    Text("Para questões sobre privacidade, entre em contato pelo email associado ao desenvolvedor na App Store.")
                }
            }
            .padding()
        }
        .navigationTitle("Privacidade")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "motorcycle")
                .font(.system(size: 64))
                .foregroundColor(.orange)

            Text("WAWA Ride")
                .font(.largeTitle).fontWeight(.bold)

            Text("versão \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1")")
                .font(.subheadline).foregroundColor(.secondary)

            Text("Passeios de moto em grupo, mais simples.\nVeja o grupo no mapa, compartilhe alertas\ne registre sua rota.")
                .font(.body).multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("Zero servidor. Zero login. 100% P2P.")
                    .font(.caption).fontWeight(.medium).foregroundColor(.orange)
                Text("Feito para motociclistas, por motociclistas.")
                    .font(.caption2).foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
    }
}
