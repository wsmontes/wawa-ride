import SwiftUI
import MapKit
import AVFoundation
import MultipeerConnectivity

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
    @State private var showMicDeniedAlert = false
    @State private var showStepList = false
    @State private var pendingHazard: (type: HazardType, coordinate: CLLocationCoordinate2D)?
    @State private var showHazardUndo = false
    @State private var hazardUndoTimer: Timer?
    @State private var riderJoinedName: String?
    @State private var showRiderJoined = false
    @State private var showFirstTimeHint = false
    @State private var periodicUpdateTimer: Timer?

    let isInRide: Bool

    // Riding mode detection
    private var isRiding: Bool { rideVM.speed > 10 }
    /// Hide non-essential UI while riding for safety
    private var isRidingAggressive: Bool { rideVM.speed > 30 }

    // Permission states
    private var gpsDenied: Bool {
        let status = LocationService.shared.authorizationStatus
        return status == .denied || status == .restricted
    }
    private var micDenied: Bool {
        AVAudioSession.sharedInstance().recordPermission == .denied
    }

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

            // ---- PERMISSION BANNERS ----

            if gpsDenied {
                VStack {
                    HStack {
                        Image(systemName: "location.slash").foregroundColor(.red)
                        Text("GPS desativado").font(.subheadline).fontWeight(.medium)
                        Spacer()
                        Button("Ajustes") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.caption).padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.orange).cornerRadius(12)
                    }
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
                    .padding(.horizontal).padding(.top, 48)
                    Spacer()
                }
            }

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
                        NavigationHUD(viewModel: rideVM,
                            onStop: { stopNavWithSummary() },
                            onOverview: { mapVM.shouldZoomToOverview = true },
                            onStepList: { showStepList = true }
                        )
                    }
                    Spacer()
                }
            }

            // Search bar (hidden during riding or active navigation)
            if !isRiding && rideVM.isNavigating && mapVM.showSearchDuringNav {
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
            } else if !isRiding && !rideVM.isNavigating {
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

            // Rider-joined banner (brief overlay when a new peer connects)
            if showRiderJoined, let name = riderJoinedName {
                VStack {
                    Spacer().frame(height: 130)
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill.checkmark").foregroundColor(.green)
                        Text("\(name) entrou no grupo")
                            .font(.subheadline).fontWeight(.medium)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial).cornerRadius(20)
                    .shadow(radius: 8)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
            }

            // Auto-presence status indicator (idle, listening for nearby riders)
            if !isInRide && mapVM.nearbyRides.isEmpty && sheetState == nil {
                VStack {
                    Spacer().frame(height: 110)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green.opacity(0.7))
                            .frame(width: 7, height: 7)
                            .overlay(
                                Circle().fill(Color.green.opacity(0.3))
                                    .frame(width: 13, height: 13)
                                    .opacity(1.0)
                            )
                        Text("Ouvindo rides próximos")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(.ultraThinMaterial).cornerRadius(16)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.5)) { showFirstTimeHint.toggle() }
                    }
                    Spacer()
                }
                .allowsHitTesting(true)
            }

            // First-time hint (shown briefly, can be dismissed)
            if !isInRide && showFirstTimeHint && mapVM.nearbyRides.isEmpty && sheetState == nil {
                VStack {
                    Spacer().frame(height: 160)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right").foregroundColor(.orange)
                            Text("Como funciona").font(.headline).foregroundColor(.white)
                            Spacer()
                            Button {
                                withAnimation { showFirstTimeHint = false }
                            } label: {
                                Image(systemName: "xmark.circle.fill").font(.title3).foregroundColor(.secondary)
                            }
                        }
                        Text("Quando outros riders abrirem o app perto de você, um banner verde aparece aqui. Toque ENTRAR e já estarão conectados — sem código, sem link, sem internet.")
                            .font(.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .background(.ultraThinMaterial)
                    .cornerRadius(14)
                    .shadow(radius: 12)
                    .padding(.horizontal, 24)
                    Spacer()
                }
                .transition(.opacity)
                .allowsHitTesting(true)
            }

            // BLE ride banner (lowest priority — only when idle, no sheets)
            if !isInRide && !mapVM.nearbyRides.isEmpty && sheetState == nil {
                VStack {
                    Spacer().frame(height: 120)
                    nearbyRidesBanner
                    Spacer()
                }
            }

            // Hazard undo toast
            if showHazardUndo, let pending = pendingHazard {
                VStack {
                    Spacer().frame(height: UIScreen.main.bounds.height * 0.6)
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(hazardLabel(pending.type))
                            .font(.subheadline).fontWeight(.medium).foregroundColor(.white)
                        Spacer()
                        Button("DESFAZER") {
                            hazardUndoTimer?.invalidate()
                            pendingHazard = nil
                            showHazardUndo = false
                            Logger.shared.ride("Hazard undone by user")
                        }
                        .font(.caption).fontWeight(.bold).foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.red.opacity(0.8)).cornerRadius(12)
                    }
                    .padding(12)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(12)
                    .padding(.horizontal, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.3), value: showHazardUndo)
                .allowsHitTesting(true)
            }

            // Rider HUD (PTT, hazards — always. Rooms only if feature flag enabled)
            if isInRide {
                VStack {
                    Spacer()
                    RiderHUD(
                        isPTTActive: $isPTTActive,
                        glowOpacity: $glowOpacity,
                        showHazardMenu: $showHazardMenu,
                        showRooms: $showRooms,
                        onEndRide: { endRide() },
                        onPTTBlocked: { showMicDeniedAlert = true },
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

            // Map controls (hidden during riding, except recenter)
            if !isRiding {
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
                        .accessibilityLabel(VoiceAssistant.shared.isMuted ? "Ativar voz" : "Desativar voz")
                        Button {
                            mapVM.cycleMapType()
                        } label: {
                            Image(systemName: mapVM.mapTypeIcon)
                                .font(.title3).padding(12)
                                .background(.ultraThinMaterial).clipShape(Circle()).shadow(radius: 4)
                        }
                        .accessibilityLabel("Alterar tipo de mapa")
                        Button {
                            mapVM.shouldRecenter = true
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.title3).padding(12)
                                .background(.ultraThinMaterial).clipShape(Circle()).shadow(radius: 4)
                        }
                        .accessibilityLabel("Centralizar na localização")
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, isInRide ? 180 : 100)
                }
            }
            } // end if !isRiding
        }
        .sheet(item: Binding(
            get: { isRiding ? nil : sheetState },
            set: { sheetState = $0 }
        )) { state in
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
                    // Start undo window instead of sending immediately
                    pendingHazard = (type, loc.coordinate)
                    showHazardUndo = true
                    // Auto-send after 3 seconds unless undone
                    hazardUndoTimer?.invalidate()
                    hazardUndoTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                        Task { @MainActor in
                            if let pending = pendingHazard {
                                HazardService.shared.markHazard(type: pending.type, at: pending.coordinate)
                                Logger.shared.ride("Hazard sent: \(pending.type)")
                            }
                            pendingHazard = nil
                            showHazardUndo = false
                        }
                    }
                }
                showHazardMenu = false
            }
        }
        .sheet(isPresented: $showRooms) { RoomListView() }
        .sheet(isPresented: $showStepList) {
            NavigationStepListView()
        }
        .alert("Microfone necessário", isPresented: $showMicDeniedAlert) {
            Button("Abrir Ajustes") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O walkie-talkie precisa de acesso ao microfone. Autorize nos Ajustes.")
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .openGeoCoordinate)) { notif in
            if let geo = notif.object as? GeoCoordinate {
                let coord = CLLocationCoordinate2D(latitude: geo.lat, longitude: geo.lng)
                let name = geo.label ?? "Coordenada"
                mapVM.pins.removeAll()
                mapVM.pins.append(ExploreMapViewModel.ExplorePin(
                    coordinate: coord,
                    title: name,
                    subtitle: "\(String(format: "%.5f", geo.lat)), \(String(format: "%.5f", geo.lng))",
                    mapItem: nil
                ))
                mapVM.shouldZoomToPins = true
                sheetState = .place(PlaceCardItem(coordinate: coord, name: name))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .meshPeerConnected)) { notif in
            if let peerID = notif.object as? MCPeerID {
                mapVM.nearbyPeers.append(peerID.displayName)
                // Show rider-joined banner briefly
                riderJoinedName = peerID.displayName
                withAnimation(.spring(response: 0.3)) { showRiderJoined = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation { showRiderJoined = false }
                }
                // Save to persistent memory
                let myName = UserDefaults.standard.string(forKey: "riderProfileName") ?? "Rider"
                try? LocalStore.shared.saveKnownPeer(
                    peerId: peerID.displayName,
                    peerName: peerID.displayName,
                    presenceId: MeshService.shared.presenceId
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .meshPeerDisconnected)) { notif in
            if let peerID = notif.object as? MCPeerID {
                mapVM.nearbyPeers.removeAll { $0 == peerID.displayName }
            }
        }
        .onAppear {
            // Start auto-presence immediately — be discoverable and discover others
            let name = UserDefaults.standard.string(forKey: "riderProfileName") ?? "Rider"
            MeshService.shared.startAutoPresence(name: name)
            mapVM.startBrowsing()
            if isInRide { setupRideSession() }
            // Always share location when peers are connected (even without a ride)
            setupAutoLocationSharing()

            // Restore navigation state if engine is still running
            // (handles view recreation after startSoloRide switches ContentView)
            if isInRide, NavigationEngine.shared.isNavigating, let route = NavigationEngine.shared.activeRoute {
                rideVM.setActiveRoute(route)
                rideVM.isNavigating = true
                rideVM.updateNavigationFromEngine()
            }

            // Auto-show first-time hint after 8s if no rides found (once per session)
            if !isInRide && !UserDefaults.standard.bool(forKey: "didShowFirstTimeHint") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                    if mapVM.nearbyRides.isEmpty && sheetState == nil {
                        withAnimation { showFirstTimeHint = true }
                        UserDefaults.standard.set(true, forKey: "didShowFirstTimeHint")
                    }
                }
            }
        }
        .onDisappear {
            periodicUpdateTimer?.invalidate()
            periodicUpdateTimer = nil
            mapVM.stopBrowsing()
            if !isInRide { MeshService.shared.stopAutoPresence() }
        }
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
                            HStack(spacing: 4) {
                                Text(ride.rideName).font(.subheadline).fontWeight(.semibold)
                                if !ride.rideCode.isEmpty {
                                    Text("· \(ride.rideCode)")
                                        .font(.caption).fontWeight(.bold)
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(Color.orange.opacity(0.2))
                                        .cornerRadius(4)
                                }
                            }
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

    /// Share location with connected peers even without an active ride
    private func setupAutoLocationSharing() {
        LocationService.shared.onLocationUpdate = { payload in
            Task { @MainActor in
                rideVM.updateLocation(speed: payload.speed, heading: payload.heading)

                // Always send location when peers are connected (auto-presence)
                if MeshService.shared.hasNearbyPeers {
                    sendAutoPresenceLocation(payload)
                }

                // If in ride mode, also do ride-specific updates
                if isInRide {
                    if RouteService.shared.isRecording {
                        RouteService.shared.addTrackPoint(latitude: payload.lat, longitude: payload.lng, speed: payload.speed, altitude: payload.altitude)
                    }
                    NavigationEngine.shared.updatePosition(CLLocation(latitude: payload.lat, longitude: payload.lng))
                    sendLocationUpdate(payload)
                }
            }
        }

        // Process incoming payloads
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

    private func sendAutoPresenceLocation(_ payload: LocationPayload) {
        guard let encoded = try? JSONEncoder().encode(payload) else { return }
        let meshPayload = MeshPayload(
            type: .locationUpdate,
            senderId: UserDefaults.standard.string(forKey: "riderProfileId") ?? "",
            senderName: UserDefaults.standard.string(forKey: "riderProfileName") ?? "Rider",
            rideId: MeshService.shared.presenceId,
            ttl: 3, priority: .normal, payload: encoded
        )
        TransportManager.shared.send(meshPayload)
    }

    private func startSoloRide() {
        AppState.shared.currentRideId = "solo-\(UUID().uuidString.prefix(8))"
        AppState.shared.currentRideName = "Navegação"
        AppState.shared.rideStartedAt = Date()
        setupRideSession()
    }

    private func setupRideSession() {
        // Don't overwrite — auto location sharing already set up in setupAutoLocationSharing
        // Just ensure tracking + periodic updates are running
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
                // Also update auto-presence peers list
                let name = payload.senderName
                if !mapVM.nearbyPeers.contains(name) {
                    mapVM.nearbyPeers.append(name)
                }
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
            // Only the ride leader can end the ride
            let leaderId = UserDefaults.standard.string(forKey: "riderProfileId") ?? ""
            if payload.senderId == leaderId || AppState.shared.participants.contains(where: { $0.riderId == payload.senderId && $0.role == .leader }) {
                NotificationCenter.default.post(name: .rideEnded, object: nil)
                Logger.shared.ride("Ride ended by leader: \(payload.senderName)")
            } else {
                Logger.shared.mesh("Rejected rideEnded from non-leader: \(payload.senderName)")
            }
        case .sweeperConfirm:
            // Only accept sweeper confirmations from the actual sweeper
            if AppState.shared.participants.contains(where: { $0.riderId == payload.senderId && $0.role == .sweeper }) {
                if let sp = try? JSONDecoder().decode(SweeperPayload.self, from: payload.payload) {
                    VoiceAssistant.shared.speak(sp.message)
                    Logger.shared.ride("Sweeper confirmation received: \(sp.message)")
                }
            } else {
                Logger.shared.mesh("Rejected sweeperConfirm from non-sweeper: \(payload.senderName)")
            }
        default: break
        }
    }

    private func startPeriodicUpdates() {
        // Prevent duplicate timers — invalidate existing before creating new
        periodicUpdateTimer?.invalidate()
        periodicUpdateTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in
                rideVM.updateParticipants(AppState.shared.participants)
                rideVM.updateAlerts(HazardService.shared.activeAlerts)
                rideVM.offRouteDistance = NavigationEngine.shared.offRouteDistance
                rideVM.updateNavigationFromEngine()

                // Check for stopped riders (2+ min immobile)
                let stopped = AppState.shared.checkStoppedRiders()
                for rider in stopped {
                    let name = rider.name
                    let dist = AppState.shared.distanceString(rider)
                    VoiceAssistant.shared.speak("\(name) está parado há mais de 2 minutos, a \(dist)")
                    AppState.shared.markStoppedNotified(rider.riderId)
                    Logger.shared.ride("Stopped rider notified: \(name) at \(dist)")
                }
            }
        }
    }

    private func stopNavWithSummary() {
        // Calculate actual traveled distance, not remaining
        if let route = NavigationEngine.shared.activeRoute {
            endNavDistance = route.distance - NavigationEngine.shared.remainingDistance
        } else {
            endNavDistance = 0
        }
        // Use ride elapsed time, not ETA
        if let startedAt = AppState.shared.rideStartedAt {
            endNavDuration = Date().timeIntervalSince(startedAt)
        } else {
            endNavDuration = 0
        }
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

    private func hazardLabel(_ type: HazardType) -> String {
        switch type {
        case .pothole: return "Buraco marcado"
        case .speedTrap: return "Radar marcado"
        case .police: return "Polícia marcada"
        case .oil: return "Óleo na pista"
        case .animal: return "Animal na pista"
        case .accident: return "Acidente marcado"
        case .danger: return "Perigo marcado"
        case .help: return "Pedido de ajuda"
        }
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

// MARK: - Navigation Step List View

struct NavigationStepListView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            let engine = NavigationEngine.shared
            let route = engine.activeRoute
            List {
                if let route {
                    Section("\(route.steps.count) passos • \(String(format: "%.1f", route.distance / 1000)) km") {
                        ForEach(Array(route.steps.enumerated()), id: \.offset) { index, step in
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(index == engine.currentStepIndex ? Color.green : Color.secondary.opacity(0.3))
                                        .frame(width: 28, height: 28)
                                    if index < engine.currentStepIndex {
                                        Image(systemName: "checkmark")
                                            .font(.caption2).fontWeight(.bold).foregroundColor(.white)
                                    } else {
                                        Text("\(index + 1)")
                                            .font(.caption2).fontWeight(.bold)
                                            .foregroundColor(index == engine.currentStepIndex ? .white : .primary)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step.instructions)
                                        .font(.subheadline)
                                        .fontWeight(index == engine.currentStepIndex ? .bold : .regular)
                                        .foregroundColor(index < engine.currentStepIndex ? .secondary : .primary)
                                    if step.distance > 0 {
                                        Text(formatDistance(step.distance))
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } else {
                    Text("Nenhuma rota ativa")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Passos da rota")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters > 1000 { return String(format: "%.1f km", meters / 1000) }
        return "\(Int(meters)) m"
    }
}

// MARK: - Navigation HUD

struct NavigationHUD: View {
    @ObservedObject var viewModel: LiveMapViewModel
    var onStop: (() -> Void)?
    var onOverview: (() -> Void)?
    var onStepList: (() -> Void)?

    var body: some View {
        if NavigationEngine.shared.isPaused {
            // Paused state
            HStack {
                Image(systemName: "pause.circle.fill").font(.title2).foregroundColor(.yellow)
                Text("Navegação pausada").font(.subheadline).fontWeight(.semibold)
                Spacer()
                Button {
                    NavigationEngine.shared.resumeNavigation()
                } label: {
                    Image(systemName: "play.circle.fill").font(.title2).foregroundColor(.green)
                }
                Button { onStop?() } label: {
                    Image(systemName: "xmark").font(.caption).padding(6)
                        .background(Color.white.opacity(0.2)).clipShape(Circle())
                }
            }
            .padding(12).background(Color.orange.opacity(0.85)).cornerRadius(12).padding(.horizontal, 8)
        } else if let instructions = viewModel.currentStepInstructions {
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
                Button { onOverview?() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption).padding(6)
                        .background(Color.white.opacity(0.2)).clipShape(Circle())
                }
                .accessibilityLabel("Visão geral da rota")
                Button { onStepList?() } label: {
                    Image(systemName: "list.bullet")
                        .font(.caption).padding(6)
                        .background(Color.white.opacity(0.2)).clipShape(Circle())
                }
                .accessibilityLabel("Lista de passos")
                Button {
                    VoiceAssistant.shared.isMuted.toggle()
                } label: {
                    Image(systemName: VoiceAssistant.shared.isMuted ? "speaker.slash" : "speaker.wave.2")
                        .font(.caption).padding(6)
                        .background(Color.white.opacity(0.2)).clipShape(Circle())
                }
                .accessibilityLabel(VoiceAssistant.shared.isMuted ? "Ativar voz" : "Desativar voz")
                Button { onStop?() } label: {
                    Image(systemName: "xmark").font(.caption).padding(6)
                        .background(Color.white.opacity(0.2)).clipShape(Circle())
                }
                .accessibilityLabel("Parar navegação")
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
    var onPTTBlocked: (() -> Void)?
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

            // Ride code (visible to leader so riders can confirm verbally)
            if let code = AppState.shared.currentRideCode, !code.isEmpty {
                HStack(spacing: 6) {
                    Text("CÓDIGO")
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                    Text(code)
                        .font(.system(size: 18, design: .monospaced)).fontWeight(.heavy)
                        .foregroundColor(.orange)
                        .tracking(4)
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Color.black.opacity(0.5))
                .cornerRadius(8)
            }

            // Action buttons
            HStack(spacing: 16) {
                Button { showHazardMenu = true } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle").font(.title2)
                        Text("Perigo").font(.caption2)
                    }
                    .frame(width: 80, height: 80).background(Color.black.opacity(0.7)).cornerRadius(40)
                }
                .accessibilityLabel("Marcar perigo")

                Button {} label: {
                    VStack(spacing: 4) {
                        Image(systemName: isPTTActive ? "mic.fill" : "mic").font(.title)
                        Text(isPTTActive ? "FALANDO" : "FALAR").font(.caption)
                    }
                    .frame(width: isPTTActive ? 110 : 90, height: isPTTActive ? 110 : 90)
                    .background(isPTTActive ? Color.green : Color.black.opacity(0.7))
                    .cornerRadius(isPTTActive ? 55 : 45)
                }
                .accessibilityLabel(isPTTActive ? "Parar de falar" : "Falar no grupo")
                .accessibilityHint("Segure para falar, solte para parar")
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isPTTActive {
                                if AVAudioSession.sharedInstance().recordPermission == .denied {
                                    onPTTBlocked?()
                                } else {
                                    startPTT()
                                }
                            }
                        }
                        .onEnded { _ in stopPTT() }
                )

                if FeatureFlags.shared.rooms {
                    Button { showRooms = true } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "message").font(.title2)
                            Text("Salas").font(.caption2)
                        }
                        .frame(width: 80, height: 80).background(Color.black.opacity(0.7)).cornerRadius(40)
                    }
                }
            }

            // Sweeper confirmation (only visible to sweepers)
            if isSweeper && !hasConfirmed {
                HStack(spacing: 12) {
                    Button {
                        AppState.shared.sweeperConfirmAll()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Todos juntos")
                        }
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.white).padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color.green).cornerRadius(20)
                    }

                    Button {
                        AppState.shared.sweeperReportMissing()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Alguém ficou")
                        }
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.white).padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color.red).cornerRadius(20)
                    }
                }
                .padding(.bottom, 4)
            } else if isSweeper && AppState.shared.sweeperConfirmedAll {
                Text("✅ Grupo completo")
                    .font(.caption).fontWeight(.medium).foregroundColor(.green)
                    .padding(.bottom, 4)
            } else if isSweeper && AppState.shared.sweeperReportedMissing {
                Text("⚠️ Reportado")
                    .font(.caption).fontWeight(.medium).foregroundColor(.red)
                    .padding(.bottom, 4)
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

    private var isSweeper: Bool {
        guard let profileId = UserDefaults.standard.string(forKey: "riderProfileId"),
              let participant = AppState.shared.participants.first(where: { $0.riderId == profileId })
        else { return false }
        return participant.role == .sweeper
    }

    private var hasConfirmed: Bool {
        AppState.shared.sweeperConfirmedAll || AppState.shared.sweeperReportedMissing
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
            // Search pins — differentiate search results from dropped pins
            let existingPins = Set(mapView.annotations.compactMap { $0 as? TypedPointAnnotation }.map { "\($0.pinType.rawValue)-\($0.title ?? "")" })
            let wantedPins = Set(mapVM.pins.flatMap { pin in
                pin.mapItem != nil
                    ? ["\(PinType.search.rawValue)-\(pin.title)"]
                    : ["\(PinType.dropped.rawValue)-\(pin.title)"]
            })
            if existingPins != wantedPins {
                mapView.removeAnnotations(mapView.annotations.filter {
                    !($0 is MKUserLocation) && !($0 is RiderAnnotation)
                })
                for pin in mapVM.pins {
                    let ann = TypedPointAnnotation()
                    ann.coordinate = pin.coordinate
                    ann.title = pin.title
                    ann.subtitle = pin.subtitle
                    ann.pinType = pin.mapItem != nil ? .search : .dropped
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

            // Overview zoom (show full route during navigation)
            if mapVM.shouldZoomToOverview, let poly = mapVM.previewPolyline ?? rideVM.routePolyline {
                let insets = UIEdgeInsets(top: 120, left: 40, bottom: 200, right: 40)
                mapView.setVisibleMapRect(poly.boundingMapRect, edgePadding: insets, animated: true)
                mapVM.shouldZoomToOverview = false
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
            if let typed = ann as? TypedPointAnnotation {
                let id = "pin-\(typed.pinType.rawValue)"
                let v = map.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: ann, reuseIdentifier: id)
                v.canShowCallout = false
                v.animatesWhenAdded = true
                switch typed.pinType {
                case .search:   v.markerTintColor = .systemRed       // search results → red
                case .dropped:  v.markerTintColor = .systemBlue      // dropped pins → blue
                case .route:    v.markerTintColor = .systemPurple    // route waypoints → purple
                }
                v.glyphImage = typed.pinType == .dropped ? UIImage(systemName: "star.fill") : nil
                return v
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

// MARK: - Typed Point Annotation (pin color differentiation)

enum PinType: String {
    case search   // red — from search results
    case dropped  // blue — user-dropped pin (long press)
    case route    // purple — route waypoints
}

final class TypedPointAnnotation: MKPointAnnotation {
    var pinType: PinType = .search
}
