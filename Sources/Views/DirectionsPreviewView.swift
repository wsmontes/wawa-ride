import SwiftUI
import MapKit

// MARK: - Directions Preview View

/// Shows route preview with ETA, distance, alternatives, and GO button.
/// Bottom sheet that appears after "Directions" is tapped from PlaceCard.

struct DirectionsPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: DirectionsPreviewViewModel

    var onStartNavigation: ((MKRoute) -> Void)?

    init(source: CLLocationCoordinate2D, destination: CLLocationCoordinate2D, destinationName: String, onStartNavigation: ((MKRoute) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: DirectionsPreviewViewModel(
            source: source,
            destination: destination,
            destinationName: destinationName
        ))
        self.onStartNavigation = onStartNavigation
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(viewModel.destinationName)
                        .font(.headline)
                    Text("De: Localização atual")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            // Loading or Routes
            if viewModel.isLoading {
                Spacer()
                ProgressView("Calculando rota...")
                Spacer()
            } else if let error = viewModel.error {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("Tentar novamente") {
                        Task { await viewModel.calculate() }
                    }
                }
                Spacer()
            } else if !viewModel.routes.isEmpty {
                // Route list
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(Array(viewModel.routes.enumerated()), id: \.offset) { index, route in
                            RouteOptionCard(
                                route: route,
                                isSelected: index == viewModel.selectedIndex,
                                index: index
                            ) {
                                viewModel.selectRoute(index)
                            }
                        }
                    }
                    .padding()
                }

                // GO button
                Button {
                    let route = viewModel.selectedRoute
                    onStartNavigation?(route)
                    dismiss()
                } label: {
                    HStack {
                        Text("IR")
                            .font(.title2)
                            .fontWeight(.heavy)
                        Image(systemName: "arrow.right")
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.green)
                    .cornerRadius(16)
                    .padding()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
        .task {
            await viewModel.calculate()
        }
    }
}

// MARK: - Route Option Card

struct RouteOptionCard: View {
    let route: MKRoute
    let isSelected: Bool
    let index: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(route.name.isEmpty ? "Rota \(index + 1)" : route.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    HStack(spacing: 12) {
                        Label(formatDistance(route.distance), systemImage: "arrow.triangle.turn.up.right.diamond")
                        Label(formatDuration(route.expectedTravelTime), systemImage: "clock")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                }
            }
            .padding()
            .background(isSelected ? Color.green.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.green : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters > 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters)) m"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)min"
        }
        return "\(minutes) min"
    }
}

// MARK: - Directions Preview ViewModel

@MainActor
final class DirectionsPreviewViewModel: ObservableObject {
    let source: CLLocationCoordinate2D
    let destination: CLLocationCoordinate2D
    let destinationName: String

    @Published var routes: [MKRoute] = []
    @Published var selectedIndex = 0
    @Published var isLoading = true
    @Published var error: String?

    private let directionsService = DirectionsService.shared

    var selectedRoute: MKRoute {
        routes[selectedIndex]
    }

    init(source: CLLocationCoordinate2D, destination: CLLocationCoordinate2D, destinationName: String) {
        self.source = source
        self.destination = destination
        self.destinationName = destinationName
    }

    func calculate() async {
        isLoading = true
        error = nil
        do {
            routes = try await directionsService.calculateRoute(
                from: source,
                to: destination,
                alternateRoutes: true
            )
            if routes.isEmpty {
                error = "Nenhuma rota encontrada"
            }
        } catch {
            self.error = "Erro ao calcular rota: \(error.localizedDescription)"
            print("🧭 Directions error: \(error)")
        }
        isLoading = false
    }

    func selectRoute(_ index: Int) {
        guard index < routes.count else { return }
        selectedIndex = index
    }
}
