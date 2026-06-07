import SwiftUI
import MultipeerConnectivity
import AVFoundation

// MARK: - Diagnostic View

/// Shows real-time system status and debug logs.
/// Accessible from Profile tab (if FeatureFlags.showDiagnostics is ON).

struct DiagnosticView: View {
    @StateObject private var state = DiagnosticState()
    @State private var showLogExport = false

    var body: some View {
        NavigationStack {
            List {
                // Connectivity
                Section("Conectividade") {
                    LabeledContent("Bluetooth", value: state.bluetoothState)
                    LabeledContent("Internet", value: state.internetState)
                    LabeledContent("GPS", value: state.gpsState)
                    LabeledContent("Mesh peers", value: "\(state.peerCount)")
                }

                // Permissions
                Section("Permissões") {
                    LabeledContent("Localização", value: state.locationPermission)
                    LabeledContent("Microfone", value: state.micPermission)
                    LabeledContent("Bluetooth", value: state.bluetoothPermission)
                }

                // Last events
                Section("Últimos eventos") {
                    LabeledContent("Último payload", value: state.lastPayloadType)
                    LabeledContent("Último peer conectado", value: state.lastPeerName)
                    LabeledContent("Mensagens processadas", value: "\(state.messagesProcessed)")
                    LabeledContent("Mensagens duplicadas", value: "\(state.messagesDeduped)")
                }

                // Log
                Section("Log (\(Logger.shared.logSize))") {
                    Text(Logger.shared.logContents)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                }

                // Actions
                Section {
                    Button("Exportar log") {
                        showLogExport = true
                    }

                    Button("Limpar log", role: .destructive) {
                        Logger.shared.clearLogs()
                    }
                }

                // Feature flags
                Section("Feature Flags (dev)") {
                    Toggle("Walkie-Talkie", isOn: Binding(
                        get: { FeatureFlags.shared.walkieTalkie },
                        set: { FeatureFlags.shared.walkieTalkie = $0 }
                    ))
                    Toggle("Comandos de Voz", isOn: Binding(
                        get: { FeatureFlags.shared.voiceCommands },
                        set: { FeatureFlags.shared.voiceCommands = $0 }
                    ))
                    Toggle("Salas", isOn: Binding(
                        get: { FeatureFlags.shared.rooms },
                        set: { FeatureFlags.shared.rooms = $0 }
                    ))
                    Toggle("Turn-by-Turn Nav", isOn: Binding(
                        get: { FeatureFlags.shared.turnByTurnNav },
                        set: { FeatureFlags.shared.turnByTurnNav = $0 }
                    ))
                    Toggle("Auto-Pause", isOn: Binding(
                        get: { FeatureFlags.shared.autoPause },
                        set: { FeatureFlags.shared.autoPause = $0 }
                    ))
                    Toggle("KML Import", isOn: Binding(
                        get: { FeatureFlags.shared.kmlImport },
                        set: { FeatureFlags.shared.kmlImport = $0 }
                    ))
                    Toggle("Export Multi-Apps", isOn: Binding(
                        get: { FeatureFlags.shared.exportMultiApps },
                        set: { FeatureFlags.shared.exportMultiApps = $0 }
                    ))

                    Button("Resetar todos", role: .destructive) {
                        FeatureFlags.shared.resetAll()
                    }
                }
            }
            .navigationTitle("Diagnóstico")
            .sheet(isPresented: $showLogExport) {
                ShareSheet(items: [Logger.shared.logFileURL])
            }
            .onAppear { state.refresh() }
        }
    }
}

// MARK: - Diagnostic State

@MainActor
final class DiagnosticState: ObservableObject {
    @Published var bluetoothState = "—"
    @Published var internetState = "—"
    @Published var gpsState = "—"
    @Published var peerCount = 0
    @Published var locationPermission = "—"
    @Published var micPermission = "—"
    @Published var bluetoothPermission = "—"
    @Published var lastPayloadType = "—"
    @Published var lastPeerName = "—"
    @Published var messagesProcessed = 0
    @Published var messagesDeduped = 0

    func refresh() {
        // Connectivity
        internetState = ConnectivityMonitor.shared.hasInternet ? "Conectado" : "Offline"

        // GPS
        let gpsStatus = LocationService.shared.authorizationStatus
        switch gpsStatus {
        case .authorizedAlways: gpsState = "Always"
        case .authorizedWhenInUse: gpsState = "When in Use"
        case .denied: gpsState = "Negado"
        case .restricted: gpsState = "Restrito"
        case .notDetermined: gpsState = "Não determinado"
        @unknown default: gpsState = "?"
        }
        locationPermission = gpsStatus == .denied || gpsStatus == .restricted ? "Negada" : "OK"

        // Mic
        let mic = AVAudioSession.sharedInstance().recordPermission
        micPermission = mic == .granted ? "OK" : mic == .denied ? "Negada" : "?"

        // Bluetooth
        bluetoothPermission = "OK" // CBManager can't check without instance; assume OK for now
        bluetoothState = "— (check Settings)"

        // Mesh
        peerCount = MeshService.shared.connectedPeers.count
        lastPeerName = MeshService.shared.connectedPeers.last?.displayName ?? "—"
    }
}

