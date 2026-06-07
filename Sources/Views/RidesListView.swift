import SwiftUI

// MARK: - Rides List View

/// Shows upcoming/active rides and ride history.
/// "Create Ride" button triggers the dedicated CreateRideView sheet.

struct RidesListView: View {
    @Binding var showCreateRide: Bool
    @StateObject private var viewModel = RidesListViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.summaries.isEmpty && AppState.shared.currentRideId == nil {
                    VStack(spacing: 16) {
                        Image(systemName: "motorcycle")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("Nenhum passeio ainda")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("Crie um passeio para começar. Riders próximos poderão entrar via Bluetooth.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        Button {
                            showCreateRide = true
                        } label: {
                            Label("Criar Passeio", systemImage: "plus.circle.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 14)
                                .background(Color.orange)
                                .cornerRadius(12)
                        }
                    }
                } else {
                    List {
                        // Active ride
                        if AppState.shared.currentRideId != nil {
                            Section("Passeio Ativo") {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(AppState.shared.currentRideName ?? "Passeio")
                                            .font(.headline)
                                        Text("Em andamento")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                    Spacer()
                                    Image(systemName: "motorcycle")
                                        .foregroundColor(.orange)
                                }
                            }
                        }

                        // History
                        if !viewModel.summaries.isEmpty {
                            Section("Histórico") {
                                ForEach(viewModel.summaries) { summary in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(summary.rideName)
                                            .font(.headline)

                                        HStack(spacing: 12) {
                                            if let distance = summary.totalDistance {
                                                Text("\(String(format: "%.1f", distance / 1000)) km")
                                            }
                                            if let duration = summary.totalDuration {
                                                Text(formatDuration(duration))
                                            }
                                            if let avgSpeed = summary.avgSpeed {
                                                Text("\(String(format: "%.0f", avgSpeed)) km/h")
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                        Text(summary.finishedAt, style: .date)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Passeios")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateRide = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                viewModel.reload()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showCreateRide)) { _ in
                showCreateRide = true
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)min"
        }
        return "\(minutes)min"
    }
}

@MainActor
final class RidesListViewModel: ObservableObject {
    @Published var summaries: [RideSummary] = []

    func reload() {
        summaries = LocalStore.shared.loadAllSummaries()
    }
}
