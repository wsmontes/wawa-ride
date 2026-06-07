import SwiftUI

// MARK: - Routes Library View

/// Shows saved routes, allows creating new ones, importing .GPX.

struct RoutesLibraryView: View {
    @StateObject private var viewModel = RoutesLibraryViewModel()
    @State private var showCreator = false
    @State private var showImporter = false
    @State private var selectedRoute: Route?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.routes.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("Nenhuma rota salva")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("Crie rotas no mapa ou importe arquivos .GPX de outros apps como Rever, Calimoto e Scenic.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        HStack(spacing: 16) {
                            Button {
                                showCreator = true
                            } label: {
                                Label("Criar Rota", systemImage: "plus")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(Color.orange)
                                    .cornerRadius(10)
                            }

                            Button {
                                showImporter = true
                            } label: {
                                Label("Importar .GPX", systemImage: "square.and.arrow.down")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(Color.orange.opacity(0.15))
                                    .cornerRadius(10)
                            }
                        }
                    }
                } else {
                    List {
                        ForEach(viewModel.routes) { route in
                            Button {
                                selectedRoute = route
                            } label: {
                                RouteRow(route: route)
                            }
                        }
                        .onDelete { indexSet in
                            // Delete route (future: confirmation)
                        }
                    }
                }
            }
            .navigationTitle("Minhas Rotas")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showCreator = true
                        } label: {
                            Label("Criar no mapa", systemImage: "map")
                        }
                        Button {
                            showImporter = true
                        } label: {
                            Label("Importar .GPX", systemImage: "doc")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreator) {
                RouteCreatorView()
            }
            .sheet(item: $selectedRoute) { route in
                RouteDetailView(route: route)
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.xml, .init(filenameExtension: "gpx")!],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    _ = RouteService.shared.importGPX(from: url)
                    viewModel.reload()
                }
            }
            .onAppear {
                viewModel.reload()
            }
        }
    }
}

// MARK: - Route Row

struct RouteRow: View {
    let route: Route

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(route.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    Label("\(route.waypoints.count) pontos", systemImage: "mappin")
                    if let distance = route.totalDistance {
                        Text("•")
                        Text("\(String(format: "%.1f", distance / 1000)) km")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)

                HStack {
                    Image(systemName: sourceIcon)
                    Text(sourceText)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    var sourceIcon: String {
        switch route.source {
        case .recorded: return "record.circle"
        case .drawn: return "hand.draw"
        case .imported: return "square.and.arrow.down"
        case .shared: return "person.2"
        }
    }

    var sourceText: String {
        switch route.source {
        case .recorded: "Gravada"
        case .drawn: "Desenhada"
        case .imported: "Importada"
        case .shared: "Compartilhada"
        }
    }
}

// MARK: - Route Detail View

struct RouteDetailView: View {
    let route: Route
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            List {
                Section("Info") {
                    LabeledContent("Nome", value: route.name)
                    LabeledContent("Origem", value: route.source.rawValue.capitalized)
                    LabeledContent("Waypoints", value: "\(route.waypoints.count)")
                    if let distance = route.totalDistance {
                        LabeledContent("Distância", value: "\(String(format: "%.1f", distance / 1000)) km")
                    }
                }

                if !route.waypoints.isEmpty {
                    Section("Waypoints") {
                        ForEach(Array(route.waypoints.sorted(by: { $0.order < $1.order }).enumerated()), id: \.element.id) { _, wp in
                            HStack {
                                Image(systemName: wp.isStop ? "stop.circle" : "mappin")
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading) {
                                    Text(wp.name ?? "Ponto \(wp.order + 1)")
                                    Text("\(String(format: "%.5f", wp.latitude)), \(String(format: "%.5f", wp.longitude))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        showShare = true
                    } label: {
                        Label("Compartilhar .GPX", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        RouteService.shared.shareRouteViaMesh(route)
                    } label: {
                        Label("Enviar via Mesh", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
            }
            .navigationTitle(route.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .sheet(isPresented: $showShare) {
                if let url = RouteService.shared.exportGPX(for: route) {
                    ShareSheet(items: [url])
                }
            }
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - ViewModel

@MainActor
final class RoutesLibraryViewModel: ObservableObject {
    @Published var routes: [Route] = []

    func reload() {
        routes = LocalStore.shared.loadAllRoutes()
    }
}
