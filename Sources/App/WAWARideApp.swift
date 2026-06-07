import SwiftUI
import AVFoundation
import CoreLocation

// MARK: - App Entry Point

@main
struct WAWARideApp: App {
    @StateObject private var appState = AppState.shared
    @State private var showProfile = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    setupApp()
                }
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    handleOpenURL(url)
                }
        }
    }

    private func setupApp() {
        // Check if profile exists
        if !LocalStore.shared.profileExists() {
            showProfile = true
        }

        // Configure audio session
        VoiceAssistant.shared.setupAudioSession()

        // Start connectivity monitoring
        ConnectivityMonitor.shared.start()

        // Request location permission
        LocationService.shared.requestPermission()
    }

    private func handleOpenURL(_ url: URL) {
        // Handle .GPX file import
        guard url.pathExtension.lowercased() == "gpx" else { return }

        if let route = RouteService.shared.importGPX(from: url) {
            VoiceAssistant.shared.speak(VoiceAssistant.routeImported(name: route.name, waypoints: route.waypoints.count))
        }
    }
}

// MARK: - Content View (Root)

struct ContentView: View {
    @StateObject private var appState = AppState.shared
    @State private var hasProfile = LocalStore.shared.profileExists()

    var body: some View {
        Group {
            if !hasProfile {
                ProfileSetupView()
                    .onDisappear {
                        hasProfile = LocalStore.shared.profileExists()
                    }
            } else if appState.currentRideId == nil {
                JoinRideView()
            } else {
                RideActiveView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .rideEnded)) { _ in
            appState.currentRideId = nil
            appState.currentRideName = nil
        }
    }
}

// MARK: - Ride Active View (Map + Controls)

struct RideActiveView: View {
    @StateObject private var viewModel = LiveMapViewModel()
    @State private var showRooms = false
    @State private var showHazardMenu = false
    @State private var showRouteCreator = false
    @State private var isPTTActive = false
    @State private var isRecordingMessage = false

    var body: some View {
        ZStack {
            // Map (full screen)
            LiveMapView(viewModel: viewModel)
                .ignoresSafeArea()

            // Top bar
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.titleBarText)
                            .font(.headline)
                            .foregroundColor(.white)

                        Text("\(viewModel.connectedCount) de \(viewModel.totalCount) online")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Rooms button
                    Button {
                        showRooms = true
                    } label: {
                        Image(systemName: AppState.shared.hasUnreadMessages ? "message.badge" : "message")
                            .font(.title2)
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal)
                .padding(.top, 48)
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0.7), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Spacer()

                // Bottom status bar
                VStack(spacing: 12) {
                    // Status text
                    Text(viewModel.statusText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)

                    // Off-route indicator
                    if viewModel.offRouteDistance > 20 {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(viewModel.offRouteDistance > 50 ? Color.red : Color.yellow)
                                .frame(width: 10, height: 10)
                            Text("\(Int(viewModel.offRouteDistance))m da rota")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                    }

                    // Action buttons
                    HStack(spacing: 16) {
                        // Hazard button
                        Button {
                            showHazardMenu = true
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.title2)
                                Text("Perigo")
                                    .font(.caption2)
                            }
                            .frame(width: 70, height: 70)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(35)
                        }

                        // PTT Button
                        Button {
                            // Hold gesture handled via LongPressGesture
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: isPTTActive ? "mic.fill" : "mic")
                                    .font(.title)
                                Text(isPTTActive ? "FALANDO" : "FALAR")
                                    .font(.caption)
                            }
                            .frame(width: isPTTActive ? 100 : 80, height: isPTTActive ? 100 : 80)
                            .background(isPTTActive ? Color.green : Color.black.opacity(0.7))
                            .cornerRadius(isPTTActive ? 50 : 40)
                        }
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    if !isPTTActive {
                                        startPTT()
                                    }
                                }
                                .onEnded { _ in
                                    stopPTT()
                                }
                        )

                        // Route button
                        Button {
                            if RouteService.shared.isRecording {
                                RouteService.shared.stopRecording()
                            } else {
                                showRouteCreator = true
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: RouteService.shared.isRecording ? "stop.circle" : "point.topleft.down.curvedto.point.bottomright.up")
                                    .font(.title2)
                                Text(RouteService.shared.isRecording ? "Parar" : "Rota")
                                    .font(.caption2)
                            }
                            .frame(width: 70, height: 70)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(35)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
        .sheet(isPresented: $showRooms) {
            RoomListView()
        }
        .sheet(isPresented: $showHazardMenu) {
            HazardMenuView { hazardType in
                if let location = LocationService.shared.currentLocation {
                    HazardService.shared.markHazard(type: hazardType, at: location.coordinate)
                }
                showHazardMenu = false
            }
        }
        .sheet(isPresented: $showRouteCreator) {
            RouteCreatorView()
        }
        .onAppear {
            setupRideSession()
        }
    }

    private func startPTT() {
        isPTTActive = true
        let roomId = AppState.shared.currentRoomId ?? AppState.shared.activeRooms.first?.id ?? "general"
        VoiceService.shared.startPTT(roomId: roomId)
    }

    private func stopPTT() {
        isPTTActive = false
        VoiceService.shared.stopPTT()
    }

    private func setupRideSession() {
        // Subscribe to location updates
        LocationService.shared.onLocationUpdate = { payload in
            Task { @MainActor in
                viewModel.updateLocation(speed: payload.speed, heading: payload.heading)

                // Add track point if recording
                if RouteService.shared.isRecording {
                    RouteService.shared.addTrackPoint(
                        latitude: payload.lat,
                        longitude: payload.lng,
                        speed: payload.speed,
                        altitude: payload.altitude
                    )
                }

                // Update navigation
                RouteService.shared.updateNavigation(
                    currentLocation: CLLocation(
                        latitude: payload.lat,
                        longitude: payload.lng
                    )
                )

                // Send location via mesh
                sendLocationUpdate(payload)
            }
        }

        // Subscribe to mesh payloads
        MeshService.shared.onPayloadReceived = { payload in
            Task { @MainActor in
                handleMeshPayload(payload)
            }
        }

        // Subscribe to mesh state
        MeshService.shared.onPeerConnected = { _ in
            Task { @MainActor in
                TransportManager.shared.onConnectivityRestored()
                viewModel.meshState = .connected
            }
        }

        // Start tracking
        LocationService.shared.startTracking()

        // Periodic UI updates
        startPeriodicUpdates()
    }

    private func sendLocationUpdate(_ payload: LocationPayload) {
        guard let encoded = try? JSONEncoder().encode(payload) else { return }
        let meshPayload = MeshPayload(
            type: .locationUpdate,
            senderId: UserDefaults.standard.string(forKey: "riderProfileId") ?? "",
            senderName: UserDefaults.standard.string(forKey: "riderProfileName") ?? "",
            rideId: AppState.shared.currentRideId ?? "",
            ttl: 3,
            priority: .normal,
            payload: encoded
        )
        TransportManager.shared.send(meshPayload)
    }

    private func handleMeshPayload(_ payload: MeshPayload) {
        switch payload.type {
        case .locationUpdate:
            if let loc = try? JSONDecoder().decode(LocationPayload.self, from: payload.payload) {
                // Update participant position
                AppState.shared.updateParticipant(senderId: payload.senderId, senderName: payload.senderName, location: loc)
                viewModel.updateParticipants(AppState.shared.participants)
            }

        case .hazardAlert:
            if let hazardPayload = try? JSONDecoder().decode(HazardAlertPayload.self, from: payload.payload) {
                HazardService.shared.handleIncomingAlert(hazardPayload.alert)
                viewModel.updateAlerts(HazardService.shared.activeAlerts)
            }

        case .hazardConfirm:
            if let action = try? JSONDecoder().decode(HazardActionPayload.self, from: payload.payload) {
                HazardService.shared.handleConfirmAction(alertId: action.alertId, riderName: action.riderName)
                viewModel.updateAlerts(HazardService.shared.activeAlerts)
            }

        case .hazardClear:
            if let action = try? JSONDecoder().decode(HazardActionPayload.self, from: payload.payload) {
                HazardService.shared.handleClearAction(alertId: action.alertId, riderName: action.riderName)
                viewModel.updateAlerts(HazardService.shared.activeAlerts)
            }

        case .voiceLive:
            if let voicePayload = try? JSONDecoder().decode(VoiceLivePayload.self, from: payload.payload) {
                VoiceService.shared.handleVoiceLivePayload(voicePayload)
            }

        case .voiceMessage:
            if let msgPayload = try? JSONDecoder().decode(VoiceMessagePayload.self, from: payload.payload) {
                VoiceService.shared.handleVoiceMessagePayload(msgPayload)
            }

        case .voiceMessageAck:
            // Handle ack (update delivery status)
            break

        case .roomCreated:
            if let roomPayload = try? JSONDecoder().decode(RoomPayload.self, from: payload.payload) {
                RoomService.shared.handleIncomingRoom(roomPayload.room)
            }

        case .roomClosed:
            if let roomPayload = try? JSONDecoder().decode(RoomMembershipPayload.self, from: payload.payload) {
                RoomService.shared.handleRoomClosed(roomPayload.roomId)
            }

        case .roomJoin:
            if let membership = try? JSONDecoder().decode(RoomMembershipPayload.self, from: payload.payload) {
                RoomService.shared.handleMembershipChange(
                    roomId: membership.roomId, riderId: membership.riderId,
                    riderName: membership.riderName, action: .join
                )
            }

        case .roomLeave:
            if let membership = try? JSONDecoder().decode(RoomMembershipPayload.self, from: payload.payload) {
                RoomService.shared.handleMembershipChange(
                    roomId: membership.roomId, riderId: membership.riderId,
                    riderName: membership.riderName, action: .leave
                )
            }

        case .routeCreated, .routeShared:
            if let routePayload = try? JSONDecoder().decode(RoutePayload.self, from: payload.payload) {
                try? LocalStore.shared.saveRoute(routePayload.route)
                if routePayload.route.createdBy == AppState.shared.currentRideId {
                    viewModel.updateRoute(trackPoints: routePayload.route.simplifiedTrack ?? [])
                }
            }

        case .routeBatch:
            if let batch = try? JSONDecoder().decode(RouteBatchPayload.self, from: payload.payload) {
                // Append track points to route
                viewModel.updateRoute(trackPoints: batch.points)
            }

        case .statusChange:
            if let status = try? JSONDecoder().decode(StatusPayload.self, from: payload.payload) {
                if status.status == "need_help" {
                    VoiceAssistant.shared.speak(VoiceAlert(
                        text: "\(payload.senderName) está parado e precisa de ajuda.",
                        priority: .high, canInterrupt: true, dedupKey: "help_\(payload.senderId)"
                    ))
                }
            }

        case .sosAlert:
            if let sos = try? JSONDecoder().decode(SOSPayload.self, from: payload.payload) {
                VoiceAssistant.shared.speak(VoiceAssistant.sosReceived(name: payload.senderName, reason: sos.reason))
            }

        case .fullState:
            if let state = try? JSONDecoder().decode(FullStatePayload.self, from: payload.payload) {
                viewModel.updateParticipants(state.participants)
                if let route = state.activeRoute {
                    viewModel.updateRoute(trackPoints: route.simplifiedTrack ?? [])
                }
                viewModel.updateAlerts(state.activeAlerts)
            }

        case .rideEnded:
            AppState.shared.currentRideId = nil
            NotificationCenter.default.post(name: .rideEnded, object: nil)

        default:
            break
        }
    }

    private func startPeriodicUpdates() {
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in
                viewModel.updateParticipants(AppState.shared.participants)
                viewModel.updateAlerts(HazardService.shared.activeAlerts)
                viewModel.offRouteDistance = RouteService.shared.offRouteDistance
                viewModel.nextTurn = RouteService.shared.nextTurn
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let rideEnded = Notification.Name("rideEnded")
}
