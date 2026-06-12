import SwiftUI

// MARK: - Routes Library View

/// Shows saved routes, allows creating new ones, importing .GPX.

struct RoutesLibraryView: View {
    @StateObject private var viewModel = RoutesLibraryViewModel()
    @State private var showCreator = false
    @State private var showImporter = false
    @State private var selectedRoute: Route?
    @State private var showDeleteConfirm: Route?
    @State private var showRename: Route?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.routes.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.system(size: 48)).foregroundColor(.secondary)
                        Text("Nenhuma rota salva").font(.headline).foregroundColor(.secondary)
                        Text("Crie rotas no mapa ou importe arquivos .GPX de outros apps como Rever, Calimoto e Scenic.")
                            .font(.subheadline).foregroundColor(.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal, 40)
                        HStack(spacing: 16) {
                            Button { showCreator = true } label: {
                                Label("Criar Rota", systemImage: "plus").font(.headline).foregroundColor(.white)
                                    .padding(.horizontal, 24).padding(.vertical, 12)
                                    .background(Color.orange).cornerRadius(10)
                            }
                            Button { showImporter = true } label: {
                                Label("Importar", systemImage: "square.and.arrow.down").font(.headline)
                                    .foregroundColor(.orange).padding(.horizontal, 24).padding(.vertical, 12)
                                    .background(Color.orange.opacity(0.15)).cornerRadius(10)
                            }
                        }
                    }
                } else {
                    List {
                        ForEach(viewModel.routes) { route in
                            Button { selectedRoute = route } label: {
                                RouteRow(route: route)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { showDeleteConfirm = route } label: {
                                    Label("Apagar", systemImage: "trash")
                                }
                                Button { showRename = route; renameText = route.name } label: {
                                    Label("Renomear", systemImage: "pencil")
                                }.tint(.orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Minhas Rotas")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showCreator = true } label: {
                            Label("Criar no mapa", systemImage: "map")
                        }
                        Button { showImporter = true } label: {
                            Label("Importar .GPX ou .KML", systemImage: "doc")
                        }
                        Divider()
                        Menu("Ordenar por") {
                            Button { viewModel.sortBy = .date } label: {
                                Label("Data", systemImage: viewModel.sortBy == .date ? "checkmark" : "")
                            }
                            Button { viewModel.sortBy = .name } label: {
                                Label("Nome", systemImage: viewModel.sortBy == .name ? "checkmark" : "")
                            }
                            Button { viewModel.sortBy = .distance } label: {
                                Label("Distância", systemImage: viewModel.sortBy == .distance ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreator) { RouteCreatorView() }
            .sheet(item: $selectedRoute) { route in RouteDetailView(route: route, onUpdate: { viewModel.reload() }) }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [
                .xml, .init(filenameExtension: "gpx")!, .init(filenameExtension: "kml")!
            ], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    _ = RouteService.shared.importGPX(from: url)
                    viewModel.reload()
                }
            }
            .confirmationDialog("Apagar rota?", isPresented: Binding(get: { showDeleteConfirm != nil }, set: { if !$0 { showDeleteConfirm = nil } })) {
                Button("Apagar", role: .destructive) {
                    if let route = showDeleteConfirm { viewModel.delete(route) }
                    showDeleteConfirm = nil
                }
                Button("Cancelar", role: .cancel) { showDeleteConfirm = nil }
            } message: {
                Text("\"\(showDeleteConfirm?.name ?? "")\" será removida permanentemente.")
            }
            .alert("Renomear rota", isPresented: Binding(get: { showRename != nil }, set: { if !$0 { showRename = nil } })) {
                TextField("Nome", text: $renameText)
                Button("Salvar") {
                    if let route = showRename { viewModel.rename(route, to: renameText) }
                    showRename = nil
                }
                Button("Cancelar", role: .cancel) { showRename = nil }
            }
            .onAppear { viewModel.reload() }
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
    var onUpdate: (() -> Void)?
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

                if let track = route.simplifiedTrack, !track.isEmpty {
                    Section("Elevação") {
                        let altitudes = track.compactMap(\.altitude)
                        if let minAlt = altitudes.min(), let maxAlt = altitudes.max(), maxAlt > minAlt {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Máx: \(Int(maxAlt))m").font(.subheadline)
                                    Spacer()
                                    Text("Mín: \(Int(minAlt))m").font(.subheadline)
                                    Spacer()
                                    Text("Ganho: \(Int(maxAlt - minAlt))m").font(.subheadline)
                                }
                                .foregroundColor(.secondary)

                                // Simple elevation bars
                                GeometryReader { geo in
                                    HStack(spacing: 1) {
                                        ForEach(Array(altitudes.enumerated()), id: \.offset) { _, alt in
                                            let height = CGFloat((alt - minAlt) / (maxAlt - minAlt)) * geo.size.height
                                            Rectangle()
                                                .fill(Color.orange.opacity(0.6))
                                                .frame(width: max(2, geo.size.width / CGFloat(max(altitudes.count, 1)) - 1),
                                                       height: max(1, height))
                                        }
                                    }
                                }
                                .frame(height: 60)
                                .cornerRadius(4)
                            }
                            .padding(.vertical, 8)
                        }
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

                Section("Abrir rota em") {
                    Button {
                        let coords = route.waypoints.sorted(by: { $0.order < $1.order }).map(\.coordinate)
                        let names = route.waypoints.sorted(by: { $0.order < $1.order }).map { $0.name ?? "" }
                        MapAppsExporter.openRouteWithWaypoints(coords, names: names, in: .appleMaps)
                    } label: {
                        Label("Apple Maps", systemImage: "map")
                    }

                    if MapAppsExporter.canOpenGoogleMaps {
                        Button {
                            let coords = route.waypoints.sorted(by: { $0.order < $1.order }).map(\.coordinate)
                            let names = route.waypoints.sorted(by: { $0.order < $1.order }).map { $0.name ?? "" }
                            MapAppsExporter.openRouteWithWaypoints(coords, names: names, in: .googleMaps)
                        } label: {
                            Label("Google Maps", systemImage: "mappin")
                        }
                    }

                    if MapAppsExporter.canOpenWaze {
                        Button {
                            let coords = route.waypoints.sorted(by: { $0.order < $1.order }).map(\.coordinate)
                            MapAppsExporter.openRouteWithWaypoints(coords, in: .waze)
                        } label: {
                            Label("Waze", systemImage: "car")
                        }
                    }
                }

                Section {
                    Button {
                        _ = try? LocalStore.shared.duplicateRoute(route)
                        onUpdate?()
                        dismiss()
                    } label: {
                        Label("Duplicar rota", systemImage: "doc.on.doc")
                    }

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
                } else {
                    VStack {
                        Text("Erro ao exportar")
                            .font(.headline)
                        Text("Não foi possível gerar o arquivo GPX.")
                            .font(.subheadline).foregroundColor(.secondary)
                        Button("OK") { showShare = false }
                            .padding(.top)
                    }
                    .padding()
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
    @Published var sortBy: SortBy = .date { didSet { reload() } }

    enum SortBy { case date, name, distance }

    func reload() {
        var result = LocalStore.shared.loadAllRoutes()
        switch sortBy {
        case .date: result.sort { $0.createdAt > $1.createdAt }
        case .name: result.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .distance: result.sort { ($0.totalDistance ?? 0) > ($1.totalDistance ?? 0) }
        }
        routes = result
    }

    func delete(_ route: Route) {
        try? LocalStore.shared.deleteRoute(route.id)
        reload()
    }

    func rename(_ route: Route, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        try? LocalStore.shared.renameRoute(route.id, newName: trimmed)
        reload()
    }

    func duplicate(_ route: Route) {
        _ = try? LocalStore.shared.duplicateRoute(route)
        reload()
    }
}
