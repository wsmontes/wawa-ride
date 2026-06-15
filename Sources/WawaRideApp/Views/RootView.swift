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
                case .navigating:
                    RidingOverlay(showEnd: $showEndConfirmation)
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

struct IdleButtons: View {
    @EnvironmentObject var session: RideSession

    var body: some View {
        HStack(spacing: 16) {
            // 60pt minimum touch target for gloved use
            Button { session.startAsLeader() } label: {
                Label("Criar", systemImage: "plus.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(.orange, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
            }
            Button { session.startAsFollower() } label: {
                Label("Entrar", systemImage: "arrow.right.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
    }
}

// MARK: - Pairing Sheet (modal over map, big PIN display)

struct PairingSheet: View {
    @EnvironmentObject var session: RideSession
    @State private var inputPIN = ""

    var body: some View {
        VStack(spacing: 20) {
            // Leader shows PIN
            if session.isLeader {
                Text("Seu PIN")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(session.pairingPIN)
                    .font(.system(size: 56, weight: .heavy, design: .monospaced))
                    .kerning(12)
                // Peer counter (visual: filled dots)
                HStack(spacing: 8) {
                    ForEach(0..<session.mesh.totalPeerCount, id: \.self) { _ in
                        Circle().fill(.green).frame(width: 12, height: 12)
                    }
                    ForEach(0..<max(0, 5 - session.mesh.totalPeerCount), id: \.self) { _ in
                        Circle().stroke(.gray, lineWidth: 1.5).frame(width: 12, height: 12)
                    }
                }
                // Start button (60pt, only when peers connected)
                Button {
                    haptic(.success)
                    session.confirmPairing()
                } label: {
                    Text("Partiu!")
                        .font(.system(size: 22, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(session.mesh.totalPeerCount > 0 ? .orange : .gray,
                                    in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(.white)
                }
                .disabled(session.mesh.totalPeerCount == 0)
            }
            // Follower enters PIN
            else {
                Text("PIN do líder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Big digit display
                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { i in
                        Text(i < inputPIN.count ? String(inputPIN[inputPIN.index(inputPIN.startIndex, offsetBy: i)]) : "·")
                            .font(.system(size: 44, weight: .bold, design: .monospaced))
                            .frame(width: 50, height: 60)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                // Custom numpad (60pt buttons, glove-friendly)
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

// MARK: - Riding Overlay (minimal: just swipe-up to end)

struct RidingOverlay: View {
    @Binding var showEnd: Bool

    var body: some View {
        // Nearly invisible handle — long press to reveal end button
        Button { showEnd = true } label: {
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 40, height: 5)
        }
        .padding(.bottom, 20)
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
