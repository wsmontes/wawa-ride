import SwiftUI
import MapKit

// MARK: - Unified Map View

/// THE map. Always present. Never replaced.
/// Rider features and navigation are overlays on this ONE map.

struct UnifiedMapView: View {
    @StateObject private var mapVM = ExploreMapViewModel()
    @StateObject private var rideVM = LiveMapViewModel()

    @State private var sheetState: SheetState?
    @State private var showHazardMenu = false
    @State private var showRooms = false
    @State private var isPTTActive = false
    @State private var glowOpacity: Double = 0
    @State private var showEndNavSummary = false
    @State private var endNavDistance: Double = 0
    @State private var endNavDuration: TimeInterval = 0
    @State private var showSaveTrackAlert = false
    @State private var trackNameInput = ""

    let isInRide: Bool

    enum SheetState: Identifiable {
        case place(PlaceCardItem)
        case directions(source: CLLocationCoordinate2D, destination: CLLocationCoordinate2D, name: String)

        var id: String {
            switch self {
            case .place(let item): return "place-\(item.id)"
            case .directions(let s, let d, let n): return "dir-\(s.latitude)-\(d.latitude)-\(n)"
            }
        }
    }

    var body: some View {
        ZStack {
            // THE MAP — always here, never changes
            UnifiedMapUIKit(
                mapVM: mapVM,
                rideVM: rideVM,
                isInRide: isInRide,
                onPlaceSelected: { sheetState = .place($0) },
                onMapTap: {
                    // Only dismiss place cards on map tap, never directions
                    if case .place = sheetState { sheetState = nil }
                }
            )
            .ignoresSafeArea(.all)

            // ---- OVERLAYS (priority: nav > search > BLE) ----

            // Navigation HUD (highest priority — always visible when navigating)
            if rideVM.isNavigating {
                VStack {
                    HStack {
                        // Collapsed search button during navigation
                        Button {
                            mapVM.showSearchDuringNav.toggle()
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.title3).padding(10)
                                .background(.ultraThinMaterial).clipShape(Circle())
                        }
                        .padding(.leading, 12)

                        Spacer()

                        // Arrival banner
                        if rideVM.remainingDistance < 50 && rideVM.remainingDistance > 0 {
                            Text("🎉 Você chegou!")
                                .font(.headline).foregroundColor(.white)
                                .padding(.horizontal, 20).padding(.vertical, 10)
                                .background(Color.green).cornerRadius(20)
                        }
                    }
                    .padding(.top, 48)

                    if !(rideVM.remainingDistance < 50 && rideVM.remainingDistance > 0) {
                        NavigationHUD(viewModel: rideVM, onStop: { stopNavWithSummary() })
                    }
                    Spacer()
                }
            }

            // Search bar (during nav: only if expanded; otherwise: always)
            if rideVM.isNavigating && mapVM.showSearchDuringNav {
                VStack {
                    SearchBarView(
                        searchText: $mapVM.searchQuery,
                        completions: mapVM.completions,
                        isSearching: mapVM.isSearching,
                        mapRegion: mapVM.currentRegion,
                        onSelectCompletion: { mapVM.selectSearchCompletion($0) { sheetState = .place($0) } },
                        onSubmit: { mapVM.searchAddress { sheetState = .place($0) } }
                    )
                    .padding(.top, 100)
                    Spacer()
                }
            } else if !rideVM.isNavigating {
                VStack {
                    SearchBarView(
                        searchText: $mapVM.searchQuery,
                        completions: mapVM.completions,
                        isSearching: mapVM.isSearching,
                        mapRegion: mapVM.currentRegion,
                        onSelectCompletion: { mapVM.selectSearchCompletion($0) { sheetState = .place($0) } },
                        onSubmit: { mapVM.searchAddress { sheetState = .place($0) } }
                    )
                    .padding(.top, 48)
                    Spacer()
                }
            }

            // BLE ride banner (lowest priority — only when idle, no sheets)
            if !isInRide && !mapVM.nearbyRides.isEmpty && sheetState == nil {
                VStack {
                    Spacer().frame(height: 120)
                    nearbyRidesBanner
                    Spacer()
                }
            }

            // Rider HUD (PTT, hazards, rooms — only during a ride)
            if isInRide {
                VStack {
                    Spacer()
                    RiderHUD(
                        isPTTActive: $isPTTActive,
                        glowOpacity: $glowOpacity,
                        showHazardMenu: $showHazardMenu,
                        showRooms: $showRooms,
                        onEndRide: { endRide() },
                        speed: rideVM.speed,
                        connectedCount: rideVM.connectedCount,
                        totalCount: rideVM.totalCount
                    )
                }

                // PTT glow
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
            }

            // End-nav summary
            if showEndNavSummary {
                VStack {
                    Spacer()
                    endNavSummaryCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 120)
                }
            }

            // Recording stats overlay
            if RouteService.shared.isRecording {
                VStack {
                    Spacer().frame(height: 48)
                    HStack {
                        Image(systemName: "record.circle")
                            .font(.title2)
                            .foregroundColor(.red)
                            .symbolEffect(.pulse, isActive: !RouteService.shared.isPaused)

                        Text(RouteService.shared.recordingStatusText)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.white)

                        Spacer()

                        Button {
                            if RouteService.shared.isPaused {
                                RouteService.shared.resumeRecording()
                            } else {
                                RouteService.shared.pauseRecording()
                            }
                        } label: {
                            Image(systemName: RouteService.shared.isPaused ? "play.circle.fill" : "pause.circle.fill")
                                .font(.title2)
                        }

                        Button {
                            showSaveTrackAlert = true
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    .padding(.horizontal, 8)
                }
            }

            // Map controls (always visible)
            VStack {
                Spacer()
                HStack {
                    // Record button (left side)
                    if !RouteService.shared.isRecording {
                        VStack(spacing: 12) {
                            Button {
                                let dateFormatter = DateFormatter()
                                dateFormatter.dateFormat = "dd/MM HH:mm"
                                let name = "Track \(dateFormatter.string(from: Date()))"
                                RouteService.shared.startRecording(name: name)
                            } label: {
                                Image(systemName: "record.circle")
                                    .font(.title2).padding(12)
                                    .background(.ultraThinMaterial).clipShape(Circle()).shadow(radius: 4)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.leading, 12)
                        .padding(.bottom, isInRide ? 180 : 100)
                    }

                    Spacer()

                    VStack(spacing: 12) {
                        Button {
                            VoiceAssistant.shared.isMuted.toggle()
                        } label: {
                            Image(systemName: VoiceAssistant.shared.isMuted ? "speaker.slash" : "speaker.wave.2")
                                .font(.title3).padding(12)
                                .background(.ultraThinMaterial).clipShape(Circle()).shadow(radius: 4)
                                .foregroundColor(VoiceAssistant.shared.isMuted ? .red : .primary)
                        }
                        Button {
                            mapVM.cycleMapType()
                        } label: {
                            Image(systemName: mapVM.mapTypeIcon)
                                .font(.title3).padding(12)
                                .background(.ultraThinMaterial).clipShape(Circle()).shadow(radius: 4)
                        }
                        Button {
                            mapVM.shouldRecenter = true
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.title3).padding(12)
                                .background(.ultraThinMaterial).clipShape(Circle()).shadow(radius: 4)
                        }
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, isInRide ? 180 : 100)
                }
            }
        }
        .sheet(item: $sheetState) { state in
            switch state {
            case .place(let item):
                PlaceCardView(item: item, onDirections: {
                    let source = LocationService.shared.currentLocation?.coordinate ?? mapVM.currentRegion?.center ?? CLLocationCoordinate2D()
                    mapVM.pendingZoomToRoute = true
                    withAnimation(.easeInOut(duration: 0.3)) {
                        sheetState = .directions(source: source, destination: item.coordinate, name: item.name)
                    }
                }, onDismiss: { sheetState = nil })

            case .directions(let source, let dest, let name):
                DirectionsPreviewView(
                    source: source, destination: dest, destinationName: name,
                    onRouteSelected: { route in
                        mapVM.previewPolyline = route.polyline
                        mapVM.pendingZoomToRoute = true
                    },
                    onStartNavigation: { route in
                        // Smooth GO transition:
                        // 1. Close sheet
                        sheetState = nil
                        // 2. Show full route on map
                        mapVM.previewPolyline = route.polyline
                        mapVM.pendingZoomToRoute = true
                        // 3. Brief pause, then start navigation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            rideVM.startNavigation(with: route)
                            if !isInRide { startSoloRide() }
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showHazardMenu) {
            HazardMenuView { type in
                if let loc = LocationService.shared.currentLocation {
                    HazardService.shared.markHazard(type: type, at: loc.coordinate)
                }
                showHazardMenu = false
            }
        }
        .sheet(isPresented: $showRooms) { RoomListView() }
        .alert("Salvar Track", isPresented: $showSaveTrackAlert) {
            TextField("Nome", text: $trackNameInput)
            Button("Salvar") {
                RouteService.shared.stopRecording(name: trackNameInput.isEmpty ? nil : trackNameInput)
                trackNameInput = ""
            }
            Button("Descartar", role: .destructive) {
                RouteService.shared.stopRecording()
            }
            Button("Cancelar", role: .cancel) { showSaveTrackAlert = false }
        } message: {
            Text("Dê um nome para o track gravado ou descarte.")
        }
        .onAppear {
            mapVM.startBrowsing()
            if isInRide { setupRideSession() }
        }
        .onDisappear { mapVM.stopBrowsing() }
    }

    // MARK: - Nearby Rides Banner

    var nearbyRidesBanner: some View {
        VStack(spacing: 8) {
            ForEach(mapVM.nearbyRides) { ride in
                Button {
                    mapVM.joinRide(ride)
                } label: {
                    HStack {
                        Image(systemName: "motorcycle").font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ride.rideName).font(.subheadline).fontWeight(.semibold)
                            Text("Líder: \(ride.leaderName) • \(ride.riderCount) riders").font(.caption)
                        }
                        Spacer()
                        Text("ENTRAR").font(.caption).fontWeight(.bold).foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Color.green).cornerRadius(16)
                    }
                    .padding(12).background(Color(.systemGray6).opacity(0.95))
                    .cornerRadius(12).padding(.horizontal)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Ride Session

    private func startSoloRide() {
        AppState.shared.currentRideId = "solo-\(UUID().uuidString.prefix(8))"
        AppState.shared.currentRideName = "Navegação"
        AppState.shared.rideStartedAt = Date()
        setupRideSession()
    }

    private func setupRideSession() {
        LocationService.shared.onLocationUpdate = { payload in
            Task { @MainActor in
                rideVM.updateLocation(speed: payload.speed, heading: payload.heading)
                if RouteService.shared.isRecording {
                    RouteService.shared.addTrackPoint(latitude: payload.lat, longitude: payload.lng, speed: payload.speed, altitude: payload.altitude)
                }
                NavigationEngine.shared.updatePosition(CLLocation(latitude: payload.lat, longitude: payload.lng))
                sendLocationUpdate(payload)
            }
        }
        MeshService.shared.onPayloadReceived = { payload in
            Task { @MainActor in handleMeshPayload(payload) }
        }
        MeshService.shared.onPeerConnected = { _ in
            Task { @MainActor in
                TransportManager.shared.onConnectivityRestored()
                rideVM.meshState = .connected
            }
        }
        LocationService.shared.startTracking()
        startPeriodicUpdates()
    }

    private func sendLocationUpdate(_ payload: LocationPayload) {
        guard let encoded = try? JSONEncoder().encode(payload) else { return }
        TransportManager.shared.send(MeshPayload(
            type: .locationUpdate, senderId: UserDefaults.standard.string(forKey: "riderProfileId") ?? "",
            senderName: UserDefaults.standard.string(forKey: "riderProfileName") ?? "",
            rideId: AppState.shared.currentRideId ?? "", ttl: 3, priority: .normal, payload: encoded
        ))
    }

    private func handleMeshPayload(_ payload: MeshPayload) {
        switch payload.type {
        case .locationUpdate:
            if let loc = try? JSONDecoder().decode(LocationPayload.self, from: payload.payload) {
                AppState.shared.updateParticipant(senderId: payload.senderId, senderName: payload.senderName, location: loc)
                rideVM.updateParticipants(AppState.shared.participants)
            }
        case .hazardAlert:
            if let hp = try? JSONDecoder().decode(HazardAlertPayload.self, from: payload.payload) {
                HazardService.shared.handleIncomingAlert(hp.alert)
                rideVM.updateAlerts(HazardService.shared.activeAlerts)
            }
        case .hazardConfirm:
            if let act = try? JSONDecoder().decode(HazardActionPayload.self, from: payload.payload) {
                HazardService.shared.handleConfirmAction(alertId: act.alertId, riderName: act.riderName)
                rideVM.updateAlerts(HazardService.shared.activeAlerts)
            }
        case .hazardClear:
            if let act = try? JSONDecoder().decode(HazardActionPayload.self, from: payload.payload) {
                HazardService.shared.handleClearAction(alertId: act.alertId, riderName: act.riderName)
                rideVM.updateAlerts(HazardService.shared.activeAlerts)
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
        case .routeCreated, .routeShared:
            if let rp = try? JSONDecoder().decode(RoutePayload.self, from: payload.payload) {
                try? LocalStore.shared.saveRoute(rp.route)
                rideVM.setTrackPolyline(trackPoints: rp.route.simplifiedTrack ?? [])
            }
        case .routeBatch:
            if let bp = try? JSONDecoder().decode(RouteBatchPayload.self, from: payload.payload) {
                rideVM.setTrackPolyline(trackPoints: bp.points)
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
                rideVM.updateParticipants(AppState.shared.participants)
                rideVM.updateAlerts(HazardService.shared.activeAlerts)
                rideVM.offRouteDistance = NavigationEngine.shared.offRouteDistance
                rideVM.updateNavigationFromEngine()
            }
        }
    }

    private func stopNavWithSummary() {
        endNavDistance = rideVM.remainingDistance
        endNavDuration = rideVM.estimatedTimeRemaining
        rideVM.stopNavigation()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showEndNavSummary = true
        }
        // Auto-dismiss after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { showEndNavSummary = false }
        }
    }

    var endNavSummaryCard: some View {
        VStack(spacing: 12) {
            Text("Navegação encerrada")
                .font(.headline)

            HStack(spacing: 24) {
                VStack {
                    Text(String(format: "%.1f", endNavDistance / 1000))
                        .font(.title2).fontWeight(.bold)
                    Text("km").font(.caption).foregroundColor(.secondary)
                }
                VStack {
                    Text(formatDuration(endNavDuration))
                        .font(.title2).fontWeight(.bold)
                    Text("est.").font(.caption).foregroundColor(.secondary)
                }
                VStack {
                    Text(endNavDuration > 0 ? "\(Int(endNavDistance / endNavDuration * 3.6))" : "--")
                        .font(.title2).fontWeight(.bold)
                    Text("km/h").font(.caption).foregroundColor(.secondary)
                }
            }

            Button("OK") {
                withAnimation { showEndNavSummary = false }
            }
            .font(.headline).foregroundColor(.white)
            .padding(.horizontal, 40).padding(.vertical, 10)
            .background(Color.orange).cornerRadius(20)
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(radius: 12)
        .padding(.horizontal, 40)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)min" }
        return "\(minutes) min"
    }

    private func endRide() {
        MeshService.shared.stopAdvertising()
        MeshService.shared.leaveMesh()
        LocationService.shared.stopTracking()
        NavigationEngine.shared.stopNavigation()

        // Calculate real ride stats
        let routeService = RouteService.shared
        let trackPoints = routeService.trackPoints
        let startedAt = AppState.shared.rideStartedAt ?? Date()
        let finishedAt = Date()
        let duration = finishedAt.timeIntervalSince(startedAt)

        // Distance from track if recording, else from current route
        let distance = routeService.isRecording ? routeService.recordingDistance : (routeService.currentRoute?.totalDistance)

        // Average speed
        let avgSpeed = duration > 0 ? (distance ?? 0) / duration * 3.6 : nil

        // Max altitude from track points
        let maxAlt = trackPoints.compactMap(\.altitude).max()

        // Stop count from route waypoints
        let stops = routeService.currentRoute?.waypoints.filter(\.isStop).count

        // Save if recording
        if routeService.isRecording {
            routeService.stopRecording()
        }

        let summary = RideSummary(
            rideId: AppState.shared.currentRideId ?? "",
            rideName: AppState.shared.currentRideName ?? "Passeio",
            startedAt: startedAt,
            finishedAt: finishedAt,
            totalDistance: distance,
            totalDuration: duration,
            maxAltitude: maxAlt,
            avgSpeed: avgSpeed,
            riderCount: max(AppState.shared.participants.count, 1),
            stopCount: stops ?? 0,
            alertCount: HazardService.shared.activeAlerts.count,
            routeId: routeService.currentRoute?.id
        )
        try? LocalStore.shared.saveRideSummary(summary)
        AppState.shared.reset()
        NotificationCenter.default.post(name: .rideEnded, object: nil)

        // Show post-ride summary card
        endNavDistance = distance ?? 0
        endNavDuration = duration
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showEndNavSummary = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            withAnimation { showEndNavSummary = false }
        }
    }
}

// MARK: - Navigation HUD

struct NavigationHUD: View {
    @ObservedObject var viewModel: LiveMapViewModel
    var onStop: (() -> Void)?

    var body: some View {
        if let instructions = viewModel.currentStepInstructions {
            HStack {
                Image(systemName: "arrow.turn.up.right").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(instructions).font(.subheadline).fontWeight(.semibold).lineLimit(2)
                    HStack {
                        Text(viewModel.navigationStatusText).font(.caption)
                        if viewModel.distanceToNextStep > 0 {
                            Text("• \(Int(viewModel.distanceToNextStep))m").font(.caption).fontWeight(.medium)
                        }
                    }
                    .foregroundColor(.white.opacity(0.8))
                }
                Spacer()
                Button {
                    VoiceAssistant.shared.isMuted.toggle()
                } label: {
                    Image(systemName: VoiceAssistant.shared.isMuted ? "speaker.slash" : "speaker.wave.2")
                        .font(.caption).padding(6)
                        .background(Color.white.opacity(0.2)).clipShape(Circle())
                }
                Button { onStop?() } label: {
                    Image(systemName: "xmark").font(.caption).padding(6)
                        .background(Color.white.opacity(0.2)).clipShape(Circle())
                }
            }
            .padding(12).background(Color.green.opacity(0.85)).cornerRadius(12).padding(.horizontal, 8)
        }
    }
}

// MARK: - Rider HUD

struct RiderHUD: View {
    @Binding var isPTTActive: Bool
    @Binding var glowOpacity: Double
    @Binding var showHazardMenu: Bool
    @Binding var showRooms: Bool
    var onEndRide: () -> Void
    var speed: Double = 0
    var connectedCount: Int = 0
    var totalCount: Int = 0

    var body: some View {
        VStack(spacing: 12) {
            // Status
            Text(statusText)
                .font(.system(.body, design: .monospaced)).foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.black.opacity(0.6)).cornerRadius(8)

            // Action buttons
            HStack(spacing: 16) {
                Button { showHazardMenu = true } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle").font(.title2)
                        Text("Perigo").font(.caption2)
                    }
                    .frame(width: 80, height: 80).background(Color.black.opacity(0.7)).cornerRadius(40)
                }

                Button {} label: {
                    VStack(spacing: 4) {
                        Image(systemName: isPTTActive ? "mic.fill" : "mic").font(.title)
                        Text(isPTTActive ? "FALANDO" : "FALAR").font(.caption)
                    }
                    .frame(width: isPTTActive ? 110 : 90, height: isPTTActive ? 110 : 90)
                    .background(isPTTActive ? Color.green : Color.black.opacity(0.7))
                    .cornerRadius(isPTTActive ? 55 : 45)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in if !isPTTActive { startPTT() } }
                        .onEnded { _ in stopPTT() }
                )

                Button { showRooms = true } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "message").font(.title2)
                        Text("Salas").font(.caption2)
                    }
                    .frame(width: 80, height: 80).background(Color.black.opacity(0.7)).cornerRadius(40)
                }
            }

            // End ride
            Button(action: onEndRide) {
                Text("Encerrar Passeio")
                    .font(.caption).foregroundColor(.red).padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.black.opacity(0.6)).cornerRadius(16)
            }
            .padding(.bottom, 24)
        }
    }

    private var statusText: String {
        var parts: [String] = []
        if speed > 0 { parts.append("\(Int(speed)) km/h") }
        if totalCount > 0 { parts.append("\(connectedCount)/\(totalCount) riders") }
        if parts.isEmpty { parts.append("WAWA Ride") }
        return parts.joined(separator: " • ")
    }

    private func startPTT() {
        isPTTActive = true
        let roomId = AppState.shared.currentRoomId ?? AppState.shared.activeRooms.first?.id ?? "general"
        VoiceService.shared.startPTT(roomId: roomId)
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { glowOpacity = 1.0 }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    private func stopPTT() {
        isPTTActive = false
        VoiceService.shared.stopPTT()
        withAnimation(.easeOut(duration: 0.3)) { glowOpacity = 0 }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Unified Map UIKit

struct UnifiedMapUIKit: UIViewRepresentable {
    @ObservedObject var mapVM: ExploreMapViewModel
    @ObservedObject var rideVM: LiveMapViewModel
    let isInRide: Bool
    var onPlaceSelected: (PlaceCardItem) -> Void
    var onMapTap: () -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.userTrackingMode = .follow
        map.showsCompass = true; map.showsScale = true
        map.showsUserTrackingButton = true; map.showsTraffic = true
        map.isPitchEnabled = true; map.isRotateEnabled = true
        map.mapType = .standard; map.showsPointsOfInterest = true
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
        context.coordinator.updateAll(map: map, mapVM: mapVM, rideVM: rideVM, isInRide: isInRide)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(mapVM: mapVM, rideVM: rideVM, isInRide: isInRide, onPlaceSelected: onPlaceSelected, onMapTap: onMapTap)
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        let mapVM: ExploreMapViewModel; let rideVM: LiveMapViewModel
        let isInRide: Bool
        let onPlaceSelected: (PlaceCardItem) -> Void; let onMapTap: () -> Void
        private var previewOverlay: MKPolyline?

        init(mapVM: ExploreMapViewModel, rideVM: LiveMapViewModel, isInRide: Bool, onPlaceSelected: @escaping (PlaceCardItem) -> Void, onMapTap: @escaping () -> Void) {
            self.mapVM = mapVM; self.rideVM = rideVM; self.isInRide = isInRide
            self.onPlaceSelected = onPlaceSelected; self.onMapTap = onMapTap
        }

        func updateAll(map mapView: MKMapView, mapVM: ExploreMapViewModel, rideVM: LiveMapViewModel, isInRide: Bool) {
            // Search pins
            let existingPins = Set(mapView.annotations.compactMap { $0 as? MKPointAnnotation }.map { $0.title ?? "" })
            let wantedPins = Set(mapVM.pins.map { $0.title })
            if existingPins != wantedPins {
                mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) && !($0 is RiderAnnotation) })
                for pin in mapVM.pins {
                    let ann = MKPointAnnotation(); ann.coordinate = pin.coordinate; ann.title = pin.title; ann.subtitle = pin.subtitle
                    mapView.addAnnotation(ann)
                }
            }
            if !mapVM.pins.isEmpty && mapVM.shouldZoomToPins {
                mapView.showAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) }, animated: true)
                mapVM.shouldZoomToPins = false
            }

            // Preview polyline
            if let old = previewOverlay { mapView.removeOverlay(old) }
            if let poly = mapVM.previewPolyline { previewOverlay = poly; mapView.addOverlay(poly) }
            else { previewOverlay = nil }

            // Map type
            if mapView.mapType != mapVM.currentMapType { mapView.mapType = mapVM.currentMapType }
            if mapVM.shouldRecenter { mapView.setUserTrackingMode(.follow, animated: true); mapVM.shouldRecenter = false }

            // Zoom to show route with bottom padding (sheet is open)
            if mapVM.pendingZoomToRoute, let poly = mapVM.previewPolyline {
                let insets = UIEdgeInsets(top: 80, left: 40, bottom: 400, right: 40)
                mapView.setVisibleMapRect(poly.boundingMapRect, edgePadding: insets, animated: true)
                mapVM.pendingZoomToRoute = false
            }
        }

        @objc func handleLongPress(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let map = g.view as? MKMapView else { return }
            let c = map.convert(g.location(in: map), toCoordinateFrom: map)
            mapVM.addDroppedPin(at: c) { self.onPlaceSelected($0) }
        }

        @objc func handleMapTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let map = g.view as? MKMapView else { return }
            let pt = g.location(in: map)
            if map.annotations.filter({ map.view(for: $0)?.frame.contains(pt) ?? false }).isEmpty { onMapTap() }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        func mapView(_ map: MKMapView, regionDidChangeAnimated: Bool) { mapVM.currentRegion = map.region }

        func mapView(_ map: MKMapView, didSelect ann: MKAnnotation) {
            guard !(ann is MKUserLocation) else { return }
            if let riderAnn = ann as? RiderAnnotation, let rider = rideVM.rider(for: riderAnn) {
                rideVM.onSelectRider?(rider)
                return
            }
            if let pin = mapVM.pins.first(where: { $0.coordinate.latitude == ann.coordinate.latitude && $0.coordinate.longitude == ann.coordinate.longitude }) {
                onPlaceSelected(PlaceCardItem(coordinate: pin.coordinate, name: pin.title, address: pin.subtitle))
            }
        }

        func mapView(_ map: MKMapView, viewFor ann: MKAnnotation) -> MKAnnotationView? {
            if ann is MKUserLocation { return nil }
            if let riderAnn = ann as? RiderAnnotation {
                return RiderAnnotationView.create(for: riderAnn, in: map)
            }
            let v = map.dequeueReusableAnnotationView(withIdentifier: "pin") as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: ann, reuseIdentifier: "pin")
            v.canShowCallout = false; v.markerTintColor = .systemOrange; v.animatesWhenAdded = true
            return v
        }

        func mapView(_ map: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let poly = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: poly)
                r.lineCap = .round
                if overlay === previewOverlay { r.strokeColor = .systemBlue; r.lineWidth = 4; r.lineDashPattern = [8, 4] }
                else { r.strokeColor = .systemPurple; r.lineWidth = 3 }
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
