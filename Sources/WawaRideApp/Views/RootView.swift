import SwiftUI
import WawaMap
import WawaMesh

/// Single-screen UI: map is ALWAYS visible, states are overlays.
/// Designed for gloved motorcycle use: 60pt touch targets, zero text input,
/// high contrast, haptic feedback, screen always on.
///
/// States: idle (buttons) → pairing (modal sheet) → riding (fullscreen map)
///
/// Reference UX patterns:
/// - Meshtastic Apple: peer count badge, connection status indicators
/// - Organic Maps: fullscreen map first, minimal chrome
/// - Waze: floating action button over map
struct RootView: View {
    @EnvironmentObject var session: RideSession
    @State private var showEndConfirmation = false

    var body: some View {
        ZStack {
            // MARK: - Map (always visible, all states)
            RideMapView(
                riders: $session.riders,
                routeCoords: $session.routeCoords
            )
            .ignoresSafeArea()

            // MARK: - Top bar (peer count badge)
            VStack {
                HStack {
                    PeerBadge(count: session.mesh.totalPeerCount, phase: session.phase)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                Spacer()
            }

            // MARK: - Bottom overlay (state-dependent)
            VStack {
                Spacer()
                switch session.phase {
                case .idle:
                    IdleButtons()
                case .pairing:
                    PairingSheet()
                case .riding:
                    RidingOverlay(showEnd: $showEndConfirmation)
                        .environmentObject(session)
                case .navigating:
                    RidingOverlay(showEnd: $showEndConfirmation)
                        .environmentObject(session)
                }
            }
        }
        .preferredColorScheme(.dark) // High contrast for sunlight
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .confirmationDialog("Encerrar passeio?", isPresented: $showEndConfirmation) {
            Button("Encerrar", role: .destructive) { session.stopRide() }
            Button("Cancelar", role: .cancel) {}
        }
    }
}

// MARK: - Peer Count Badge

struct PeerBadge: View {
    let count: Int
    let phase: RideSession.Phase

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(badgeColor)
                .frame(width: 10, height: 10)
            Text("\(count)")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 12))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var badgeColor: Color {
        if count == 0 { return .yellow }
        if phase == .riding { return .green }
        return .blue
    }
}

// MARK: - Idle State (two big buttons over map)
/// Inspired by Organic Maps: minimal floating buttons over fullscreen map.
/// 60pt height minimum for gloved motorcycle use.
struct IdleButtons: View {
    @EnvironmentObject var session: RideSession

    var body: some View {
        VStack(spacing: 12) {
            // App name (subtle, disappears once riding)
            Text("WAWA RIDE")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .kerning(3)

            HStack(spacing: 12) {
                Button { session.startAsLeader() } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                        Text("Criar")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(.orange, in: RoundedRectangle(cornerRadius: 18))
                    .foregroundStyle(.white)
                }
                Button { session.startAsFollower() } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 24))
                        Text("Entrar")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 18))
                    .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
    }
}

// MARK: - Pairing Sheet (modal over map, big PIN display)
/// Inspired by:
/// - SwiftPinput (hadiuzzaman524): individual digit boxes with active border animation
/// - CodeScanner (twostraws): vibrate on success (haptic feedback pattern)
/// - UIOnboarding (lascic): large, accessible, Apple-style
struct PairingSheet: View {
    @EnvironmentObject var session: RideSession
    @State private var inputPIN = ""
    @State private var pinScale = 1.0

    var body: some View {
        VStack(spacing: 20) {
            // Leader shows PIN (big, pulsing on new peer connect)
            if session.isLeader {
                Text("Seu PIN")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Large PIN display (inspired by SwiftPinput style2: rounded boxes)
                HStack(spacing: 10) {
                    ForEach(Array(session.pairingPIN), id: \.self) { digit in
                        Text(String(digit))
                            .font(.system(size: 44, weight: .heavy, design: .monospaced))
                            .frame(width: 56, height: 64)
                            .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.orange, lineWidth: 2))
                    }
                }
                .scaleEffect(pinScale)
                .onChange(of: session.mesh.totalPeerCount) { _, _ in
                    // Pulse PIN when new peer connects (Meshtastic pattern)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { pinScale = 1.1 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.spring()) { pinScale = 1.0 }
                    }
                    haptic(.success)
                }
                // Peer counter (visual: filled circles)
                HStack(spacing: 8) {
                    ForEach(0..<session.mesh.totalPeerCount, id: \.self) { _ in
                        Circle().fill(.green).frame(width: 12, height: 12)
                    }
                    ForEach(0..<max(0, 5 - session.mesh.totalPeerCount), id: \.self) { _ in
                        Circle().stroke(.gray, lineWidth: 1.5).frame(width: 12, height: 12)
                    }
                }
                .padding(.top, 4)
                // Start ride button
                Button {
                    haptic(.success)
                    session.confirmPairing()
                } label: {
                    Text("Partiu! 🏍️")
                        .font(.system(size: 22, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(session.mesh.totalPeerCount > 0 ? .orange : .gray.opacity(0.5),
                                    in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(.white)
                }
                .disabled(session.mesh.totalPeerCount == 0)
            }
            // Follower enters PIN (custom NumPad, no keyboard)
            else {
                Text("PIN do líder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Big digit display (SwiftPinput-style individual boxes)
                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { i in
                        let hasDigit = i < inputPIN.count
                        Text(hasDigit ? String(inputPIN[inputPIN.index(inputPIN.startIndex, offsetBy: i)]) : "")
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .frame(width: 52, height: 60)
                            .background(hasDigit ? .blue.opacity(0.15) : .white.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(hasDigit ? .blue : .gray.opacity(0.4), lineWidth: 2))
                    }
                }
                // Glove-friendly numpad
                NumPad(value: $inputPIN, onComplete: {
                    haptic(.success)
                    session.joinWithPIN(inputPIN)
                })
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }
}

// MARK: - Riding Overlay (minimal chrome: speed + distance + hidden end button)
/// Inspired by:
/// - GoCycling (AnthonyH93): floating metrics overlay on top of map
/// - Velik (avdyushin): dark gauges, speed display, split view
/// - Organic Maps: minimal chrome, glanceable, fullscreen map
struct RidingOverlay: View {
    @EnvironmentObject var session: RideSession
    @Binding var showEnd: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Speed + Distance HUD (glanceable at handlebar distance)
            HStack(spacing: 24) {
                // Speed (large, primary info while riding)
                VStack(spacing: 0) {
                    Text(speedText)
                        .font(.system(size: 32, weight: .heavy, design: .monospaced))
                    Text("km/h")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                // Rider count
                VStack(spacing: 0) {
                    Text("\(session.riders.count)")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                    Text("riders")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.bottom, 12)

            // Nearly invisible end-ride handle (long press reveals dialog)
            Button { showEnd = true } label: {
                Capsule()
                    .fill(.white.opacity(0.3))
                    .frame(width: 40, height: 5)
            }
            .padding(.bottom, 20)
        }
    }

    private var speedText: String {
        guard let speed = session.riders.first(where: { $0.id == session.mesh.ble.localPeerID.hex })?.speed,
              speed > 0 else { return "--" }
        return "\(Int(speed * 3.6))" // m/s → km/h
    }
}

// MARK: - Custom NumPad (60pt targets, glove-safe)

struct NumPad: View {
    @Binding var value: String
    let onComplete: () -> Void

    private let rows = [["1","2","3"], ["4","5","6"], ["7","8","9"], ["⌫","0","✓"]]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            haptic(.light)
                            handleKey(key)
                        } label: {
                            Text(key)
                                .font(.system(size: 24, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 60)
                                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(key == "✓" ? .green : .white)
                        }
                        .disabled(key == "✓" && value.count != 4)
                    }
                }
            }
        }
    }

    private func handleKey(_ key: String) {
        switch key {
        case "⌫": if !value.isEmpty { value.removeLast() }
        case "✓": if value.count == 4 { onComplete() }
        default: if value.count < 4 { value.append(key) }
        }
    }
}

// MARK: - Haptic Helper

func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
    UINotificationFeedbackGenerator().notificationOccurred(type)
}
