import SwiftUI
import MapKit

// MARK: - Ride Active View (Fullscreen overlay during an active ride)

struct RideActiveView: View {
    @StateObject private var viewModel = LiveMapViewModel()
    @State private var showRooms = false
    @State private var showHazardMenu = false
    @State private var showRouteCreator = false
    @State private var isPTTActive = false

    @State private var glowOpacity: Double = 0

    var body: some View {
        ZStack {
            LiveMapView(viewModel: viewModel)
                .ignoresSafeArea()

            // PTT active glow border
            if isPTTActive {
                Rectangle()
                    .fill(Color.clear)
                    .background(
                        RoundedRectangle(cornerRadius: 0)
                            .stroke(Color.green.opacity(0.6), lineWidth: 6)
                            .blur(radius: 8)
                            .opacity(glowOpacity)
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack {
                // Top bar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.titleBarText)
                            .font(.headline).foregroundColor(.white)
                        Text("\(viewModel.connectedCount) de \(viewModel.totalCount) online")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()

                    // Rooms
                    Button {
                        showRooms = true
                    } label: {
                        Image(systemName: AppState.shared.hasUnreadMessages ? "message.badge" : "message")
                            .font(.title2).padding(8)
                            .background(Color.black.opacity(0.6)).clipShape(Circle())
                    }

                    // End ride
                    Button {
                        endRide()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2).padding(8)
                            .foregroundColor(.red)
                            .background(Color.black.opacity(0.6)).clipShape(Circle())
                    }
                }
                .padding(.horizontal).padding(.top, 48)
                .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))

                // Navigation instruction banner
                if viewModel.isNavigating, let instructions = viewModel.currentStepInstructions {
                    HStack {
                        Image(systemName: "arrow.turn.up.right")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(instructions)
                                .font(.subheadline).fontWeight(.semibold)
                                .lineLimit(2)
                            HStack {
                                Text(viewModel.navigationStatusText)
                                    .font(.caption)
                                if viewModel.distanceToNextStep > 0 {
                                    Text("•")
                                    Text("\(Int(viewModel.distanceToNextStep))m")
                                        .font(.caption).fontWeight(.medium)
                                }
                            }
                            .foregroundColor(.white.opacity(0.8))
                        }
                        Spacer()
                        Button {
                            viewModel.stopNavigation()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption).padding(6)
                                .background(Color.white.opacity(0.2)).clipShape(Circle())
                        }
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.85))
                    .cornerRadius(12)
                    .padding(.horizontal, 8)
                }

                Spacer()

                // Bottom controls
                VStack(spacing: 12) {
                    // Status
                    Text(viewModel.statusText)
                        .font(.system(.body, design: .monospaced)).foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.black.opacity(0.6)).cornerRadius(8)

                    if viewModel.offRouteDistance > 20 {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(viewModel.offRouteDistance > 50 ? Color.red : Color.yellow)
                                .frame(width: 10, height: 10)
                            Text("\(Int(viewModel.offRouteDistance))m da rota")
                                .font(.caption).foregroundColor(.white)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Color.black.opacity(0.6)).cornerRadius(8)
                    }

                    // Action buttons
                    HStack(spacing: 16) {
                        Button {
                            showHazardMenu = true
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle").font(.title2)
                                Text("Perigo").font(.caption2)
                            }
                            .frame(width: 70, height: 70)
                            .background(Color.black.opacity(0.7)).cornerRadius(35)
                        }

                        // PTT
                        Button {} label: {
                            VStack(spacing: 4) {
                                Image(systemName: isPTTActive ? "mic.fill" : "mic").font(.title)
                                Text(isPTTActive ? "FALANDO" : "FALAR").font(.caption)
                            }
                            .frame(width: isPTTActive ? 100 : 80, height: isPTTActive ? 100 : 80)
                            .background(isPTTActive ? Color.green : Color.black.opacity(0.7))
                            .cornerRadius(isPTTActive ? 50 : 40)
                        }
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in if !isPTTActive { startPTT() } }
                                .onEnded { _ in stopPTT() }
                        )

                        // Route
                        Button {
                            if RouteService.shared.isRecording {
                                RouteService.shared.stopRecording()
                            } else {
                                showRouteCreator = true
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: RouteService.shared.isRecording ? "stop.circle" : "point.topleft.down.curvedto.point.bottomright.up").font(.title2)
                                Text(RouteService.shared.isRecording ? "Parar" : "Rota").font(.caption2)
                            }
                            .frame(width: 70, height: 70)
                            .background(Color.black.opacity(0.7)).cornerRadius(35)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
        .sheet(isPresented: $showRooms) { RoomListView() }
        .sheet(isPresented: $showHazardMenu) {
            HazardMenuView { type in
                if let loc = LocationService.shared.currentLocation {
                    HazardService.shared.markHazard(type: type, at: loc.coordinate)
                }
                showHazardMenu = false
            }
        }
        .sheet(isPresented: $showRouteCreator) { RouteCreatorView() }
        .onAppear {
            setupRideSession()
            // If launched with a pending navigation route, start it
            if let route = AppState.shared.pendingNavigationRoute {
                viewModel.startNavigation(with: route)
                AppState.shared.pendingNavigationRoute = nil
            }
        }
    }

    private func startPTT() {
        isPTTActive = true
        let roomId = AppState.shared.currentRoomId ?? AppState.shared.activeRooms.first?.id ?? "general"
        VoiceService.shared.startPTT(roomId: roomId)

        // Pulse glow animation
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
            glowOpacity = 1.0
        }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    private func stopPTT() {
        isPTTActive = false
        VoiceService.shared.stopPTT()
        withAnimation(.easeOut(duration: 0.3)) {
            glowOpacity = 0
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func endRide() {
        MeshService.shared.stopAdvertising()
        MeshService.shared.leaveMesh()
        LocationService.shared.stopTracking()
        NavigationEngine.shared.stopNavigation()
        RouteService.shared.stopRecording()

        // Save summary
        let summary = RideSummary(
            rideId: AppState.shared.currentRideId ?? "",
            rideName: AppState.shared.currentRideName ?? "Passeio",
            startedAt: Date().addingTimeInterval(-3600),
            finishedAt: Date(),
            totalDistance: RouteService.shared.currentRoute?.totalDistance,
            totalDuration: 3600,
            maxAltitude: nil,
            avgSpeed: nil,
            riderCount: AppState.shared.participants.count,
            stopCount: 0,
            alertCount: HazardService.shared.activeAlerts.count,
            routeId: RouteService.shared.currentRoute?.id
        )
        try? LocalStore.shared.saveRideSummary(summary)

        AppState.shared.reset()
        NotificationCenter.default.post(name: .rideEnded, object: nil)
    }

    private func setupRideSession() {
        LocationService.shared.onLocationUpdate = { payload in
            Task { @MainActor in
                viewModel.updateLocation(speed: payload.speed, heading: payload.heading)

                if RouteService.shared.isRecording {
                    RouteService.shared.addTrackPoint(latitude: payload.lat, longitude: payload.lng, speed: payload.speed, altitude: payload.altitude)
                }

                let location = CLLocation(latitude: payload.lat, longitude: payload.lng)
                NavigationEngine.shared.updatePosition(location)

                sendLocationUpdate(payload)
            }
        }

        MeshService.shared.onPayloadReceived = { payload in
            Task { @MainActor in handleMeshPayload(payload) }
        }

        MeshService.shared.onPeerConnected = { _ in
            Task { @MainActor in
                TransportManager.shared.onConnectivityRestored()
                viewModel.meshState = .connected
            }
        }

        LocationService.shared.startTracking()
        startPeriodicUpdates()
    }

    private func sendLocationUpdate(_ payload: LocationPayload) {
        guard let encoded = try? JSONEncoder().encode(payload) else { return }
        let meshPayload = MeshPayload(
            type: .locationUpdate,
            senderId: UserDefaults.standard.string(forKey: "riderProfileId") ?? "",
            senderName: UserDefaults.standard.string(forKey: "riderProfileName") ?? "",
            rideId: AppState.shared.currentRideId ?? "",
            ttl: 3, priority: .normal, payload: encoded
        )
        TransportManager.shared.send(meshPayload)
    }

    private func handleMeshPayload(_ payload: MeshPayload) {
        switch payload.type {
        case .locationUpdate:
            if let loc = try? JSONDecoder().decode(LocationPayload.self, from: payload.payload) {
                AppState.shared.updateParticipant(senderId: payload.senderId, senderName: payload.senderName, location: loc)
                viewModel.updateParticipants(AppState.shared.participants)
            }
        case .hazardAlert:
            if let hp = try? JSONDecoder().decode(HazardAlertPayload.self, from: payload.payload) {
                HazardService.shared.handleIncomingAlert(hp.alert)
                viewModel.updateAlerts(HazardService.shared.activeAlerts)
            }
        case .hazardConfirm:
            if let act = try? JSONDecoder().decode(HazardActionPayload.self, from: payload.payload) {
                HazardService.shared.handleConfirmAction(alertId: act.alertId, riderName: act.riderName)
                viewModel.updateAlerts(HazardService.shared.activeAlerts)
            }
        case .hazardClear:
            if let act = try? JSONDecoder().decode(HazardActionPayload.self, from: payload.payload) {
                HazardService.shared.handleClearAction(alertId: act.alertId, riderName: act.riderName)
                viewModel.updateAlerts(HazardService.shared.activeAlerts)
            }
        case .voiceLive:
            if let vp = try? JSONDecoder().decode(VoiceLivePayload.self, from: payload.payload) {
                VoiceService.shared.handleVoiceLivePayload(vp)
            }
        case .voiceMessage:
            if let mp = try? JSONDecoder().decode(VoiceMessagePayload.self, from: payload.payload) {
                VoiceService.shared.handleVoiceMessagePayload(mp)
            }
        case .roomCreated:
            if let rp = try? JSONDecoder().decode(RoomPayload.self, from: payload.payload) {
                RoomService.shared.handleIncomingRoom(rp.room)
            }
        case .roomClosed:
            if let rp = try? JSONDecoder().decode(RoomMembershipPayload.self, from: payload.payload) {
                RoomService.shared.handleRoomClosed(rp.roomId)
            }
        case .routeCreated, .routeShared:
            if let rp = try? JSONDecoder().decode(RoutePayload.self, from: payload.payload) {
                try? LocalStore.shared.saveRoute(rp.route)
                viewModel.setTrackPolyline(trackPoints: rp.route.simplifiedTrack ?? [])
            }
        case .routeBatch:
            if let bp = try? JSONDecoder().decode(RouteBatchPayload.self, from: payload.payload) {
                viewModel.setTrackPolyline(trackPoints: bp.points)
            }
        case .sosAlert:
            if let sos = try? JSONDecoder().decode(SOSPayload.self, from: payload.payload) {
                VoiceAssistant.shared.speak(VoiceAssistant.sosReceived(name: payload.senderName, reason: sos.reason))
            }
        case .rideEnded:
            NotificationCenter.default.post(name: .rideEnded, object: nil)
        default: break
        }
    }

    private func startPeriodicUpdates() {
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in
                viewModel.updateParticipants(AppState.shared.participants)
                viewModel.updateAlerts(HazardService.shared.activeAlerts)
                viewModel.offRouteDistance = NavigationEngine.shared.offRouteDistance
                viewModel.updateNavigationFromEngine()
            }
        }
    }
}
