import SwiftUI
import MapKit

// MARK: - Directions Preview View 2.0

struct DirectionsPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: DirectionsPreviewViewModel
    var onRouteSelected: ((MKRoute) -> Void)?
    var onStartNavigation: ((MKRoute) -> Void)?

    @State private var showAllSteps = false

    init(source: CLLocationCoordinate2D, destination: CLLocationCoordinate2D, destinationName: String, onRouteSelected: ((MKRoute) -> Void)? = nil, onStartNavigation: ((MKRoute) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: DirectionsPreviewViewModel(
            source: source, destination: destination, destinationName: destinationName
        ))
        self.onRouteSelected = onRouteSelected
        self.onStartNavigation = onStartNavigation
    }

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            HStack {
                VStack(alignment: .leading) {
                    Text(viewModel.destinationName).font(.headline)
                    Text("De: Localização atual").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary)
                }
            }
            .padding()

            if viewModel.isLoading {
                Spacer()
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.3)
                    Text("Calculando melhor rota...")
                        .font(.subheadline).foregroundColor(.secondary)
                    Text("Usando MapKit para traçar o caminho mais rápido")
                        .font(.caption).foregroundColor(.secondary.opacity(0.7))
                }
                Spacer()
            } else if let error = viewModel.error {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundColor(.orange)
                    Text(error).font(.subheadline).foregroundColor(.secondary)
                    Button("Tentar novamente") { Task { await viewModel.calculate() } }
                }
                Spacer()
            } else if !viewModel.routes.isEmpty {
                ScrollView {
                    VStack(spacing: 12) {
                        // Mini route snapshot — shows selected route inside the card
                        if let snapshot = viewModel.routeSnapshot {
                            Image(uiImage: snapshot)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 160)
                                .cornerRadius(12)
                                .padding(.horizontal)
                                .onAppear {
                                    // Generate snapshot on appear if not yet done
                                    if viewModel.routeSnapshot == nil, let route = viewModel.selectedRoute {
                                        Task { await viewModel.generateSnapshot(for: route) }
                                    }
                                }
                        }

                        // Route options
                        // Route options
                        ForEach(Array(viewModel.routes.enumerated()), id: \.offset) { index, route in
                            RouteOptionCard(
                                route: route,
                                isSelected: index == viewModel.selectedIndex,
                                index: index
                            ) {
                                viewModel.selectRoute(index)
                                onRouteSelected?(route)
                            }
                        }

                        // Step list preview
                        if let selected = viewModel.selectedRoute {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    Text("Passos")
                                        .font(.headline)
                                    Spacer()
                                    if selected.steps.count > 3 {
                                        Button(showAllSteps ? "Mostrar menos" : "Ver todos (\(selected.steps.count))") {
                                            withAnimation { showAllSteps.toggle() }
                                        }
                                        .font(.subheadline)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.top, 8)

                                let steps = showAllSteps ? selected.steps : Array(selected.steps.prefix(3))
                                ForEach(Array(steps.enumerated()), id: \.offset) { stepIndex, step in
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .fill(stepIndex == 0 ? Color.green : Color.secondary.opacity(0.3))
                                                .frame(width: 24, height: 24)
                                            Text("\(stepIndex + 1)")
                                                .font(.caption2).fontWeight(.bold)
                                                .foregroundColor(stepIndex == 0 ? .white : .primary)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(step.instructions)
                                                .font(.subheadline)
                                                .lineLimit(2)
                                            if step.distance > 0 {
                                                Text(formatDistance(step.distance))
                                                    .font(.caption).foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 6)

                                    if stepIndex < steps.count - 1 {
                                        Divider().padding(.leading, 48)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }

                // GO button
                Button {
                    if let route = viewModel.selectedRoute {
                        onStartNavigation?(route)
                    }
                    dismiss()
                } label: {
                    HStack {
                        Text("IR").font(.title2).fontWeight(.heavy)
                        Image(systemName: "arrow.right")
                    }
                    .foregroundColor(.white).frame(maxWidth: .infinity)
                    .padding(.vertical, 16).background(Color.green).cornerRadius(16)
                    .padding()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
        .task { await viewModel.calculate() }
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters > 1000 { return String(format: "%.1f km", meters / 1000) }
        if meters > 0 { return "\(Int(meters)) m" }
        return ""
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
                        .font(.headline).foregroundColor(.primary)
                    HStack(spacing: 12) {
                        Label(formatDistance(route.distance), systemImage: "arrow.triangle.turn.up.right.diamond")
                        Label(formatDuration(route.expectedTravelTime), systemImage: "clock")
                    }
                    .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundColor(.green)
                }
            }
            .padding()
            .background(isSelected ? Color.green.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.green : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        meters > 1000 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters)) m"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)min" : "\(minutes) min"
    }
}

// MARK: - ViewModel

@MainActor
final class DirectionsPreviewViewModel: ObservableObject {
    let source: CLLocationCoordinate2D
    let destination: CLLocationCoordinate2D
    let destinationName: String

    @Published var routes: [MKRoute] = []
    @Published var selectedIndex = 0
    @Published var isLoading = true
    @Published var error: String?
    @Published var routeSnapshot: UIImage?

    private let directionsService = DirectionsService.shared

    var selectedRoute: MKRoute? {
        guard selectedIndex < routes.count else { return nil }
        return routes[selectedIndex]
    }

    init(source: CLLocationCoordinate2D, destination: CLLocationCoordinate2D, destinationName: String) {
        self.source = source
        self.destination = destination
        self.destinationName = destinationName
    }

    func calculate() async {
        isLoading = true; error = nil
        do {
            routes = try await directionsService.calculateRoute(from: source, to: destination, alternateRoutes: true)
            if routes.isEmpty { error = "Nenhuma rota encontrada" }
            else if let first = routes.first {
                await generateSnapshot(for: first)
            }
        } catch {
            self.error = "Erro ao calcular rota: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func selectRoute(_ index: Int) {
        guard index < routes.count else { return }
        selectedIndex = index
        Task { await generateSnapshot(for: routes[index]) }
    }

    func generateSnapshot(for route: MKRoute) async {
        let polyline = route.polyline
        let rect = polyline.boundingMapRect
        let options = MKMapSnapshotter.Options()
        options.mapRect = rect
        options.size = CGSize(width: 360, height: 160)
        options.scale = UIScreen.main.scale
        options.mapType = .mutedStandard
        options.showsBuildings = true

        let snapshotter = MKMapSnapshotter(options: options)
        do {
            let snapshot = try await snapshotter.start()
            let image = await UIGraphicsImageRenderer(size: options.size).image { ctx in
                snapshot.image.draw(at: .zero)
                // Draw the route polyline on the snapshot
                let points = polyline.points()
                let path = UIBezierPath()
                for i in 0..<polyline.pointCount {
                    let point = points[i]
                    let cgPoint = snapshot.point(for: point.coordinate)
                    if i == 0 { path.move(to: cgPoint) }
                    else { path.addLine(to: cgPoint) }
                }
                path.lineWidth = 4
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                UIColor.systemBlue.setStroke()
                path.stroke()
            }
            self.routeSnapshot = image
        } catch {
            Logger.shared.nav("Snapshot failed: \(error.localizedDescription)")
        }
    }
}
