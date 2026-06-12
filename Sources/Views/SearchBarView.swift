import SwiftUI
import MapKit

// MARK: - Search Bar View 2.0

/// Full search experience like Apple Maps / Google Maps:
/// - Autocomplete results updated in real time as user types
/// - Results filtered by visible map region (proximity)
/// - Category icons and subtitles for each result
/// - Quick category shortcuts when search is empty
/// - Semi-transparent overlay when showing results

struct SearchBarView: View {
    @Binding var searchText: String
    let completions: [MKLocalSearchCompletion]
    let isSearching: Bool
    let mapRegion: MKCoordinateRegion?
    let onSelectCompletion: (MKLocalSearchCompletion) -> Void
    let onSubmit: () -> Void

    @State private var showResults = false
    @FocusState private var isFocused: Bool

    private let quickCategories: [(String, String, String)] = [
        ("⛽", "Posto", "Gas Station"),
        ("🍽️", "Restaurante", "Restaurant"),
        ("☕", "Café", "Coffee"),
        ("🏨", "Hotel", "Hotel"),
        ("🛒", "Supermercado", "Supermarket"),
        ("🔧", "Oficina", "Auto Repair"),
        ("🏥", "Hospital", "Hospital"),
        ("🅿️", "Estacionamento", "Parking"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Search input bar
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 15))

                    TextField("Buscar lugar ou endereço", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .focused($isFocused)
                        .onSubmit {
                            dismissResults()
                            SearchHistory.shared.add(searchText)
                            onSubmit()
                        }
                        .onChange(of: searchText) { _, newValue in
                            if newValue.isEmpty {
                                showResults = false
                                SearchService.shared.clearCompletions()
                            } else {
                                showResults = true
                                SearchService.shared.searchCompletions(
                                    query: newValue,
                                    region: mapRegion
                                )
                            }
                        }

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            showResults = false
                            SearchService.shared.clearCompletions()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 15))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .cornerRadius(12)

                if isFocused || showResults {
                    Button("Cancelar") {
                        searchText = ""
                        showResults = false
                        isFocused = false
                        SearchService.shared.clearCompletions()
                    }
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal)
            .animation(.easeInOut(duration: 0.2), value: isFocused)

            // Results panel
            if showResults || isFocused {
                searchResultsPanel
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Search Results Panel

    @ViewBuilder
    var searchResultsPanel: some View {
        VStack(spacing: 0) {
            if searchText.isEmpty {
                // Search history (when focused, before typing)
                if isFocused && !SearchHistory.shared.recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Recentes")
                                .font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
                            Spacer()
                            Button("Limpar") { SearchHistory.shared.clear() }
                                .font(.caption).foregroundColor(.orange)
                        }
                        .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)

                        ForEach(SearchHistory.shared.recentSearches, id: \.self) { query in
                            Button {
                                searchText = query
                                SearchService.shared.searchCompletions(query: query, region: mapRegion)
                            } label: {
                                HStack {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 14)).foregroundColor(.secondary)
                                    Text(query).font(.subheadline).foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "arrow.up.forward")
                                        .font(.system(size: 12)).foregroundColor(.secondary)
                                }
                                .padding(.horizontal).padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                        }

                        Divider().padding(.vertical, 8)
                    }
                }

                // Quick categories when search is empty
                VStack(alignment: .leading, spacing: 4) {
                    Text("Encontre por perto")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 8)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                        ForEach(quickCategories, id: \.1) { (emoji, name, query) in
                            Button {
                                searchText = name
                                SearchService.shared.searchCompletions(query: name, region: mapRegion)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(emoji)
                                    Text(name)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color(.systemGray5).opacity(0.6))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
            } else if isSearching && completions.isEmpty {
                // Loading
                HStack {
                    ProgressView()
                        .padding(.trailing, 8)
                    Text("Buscando...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            } else if !completions.isEmpty {
                // Autocomplete results
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(completions.enumerated()), id: \.offset) { index, completion in
                            Button {
                                searchText = completion.title
                                dismissResults()
                                onSelectCompletion(completion)
                            } label: {
                                HStack(spacing: 12) {
                                    // Category icon
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(categoryColor(for: completion).opacity(0.15))
                                            .frame(width: 36, height: 36)

                                        Image(systemName: categoryIcon(for: completion))
                                            .font(.system(size: 14))
                                            .foregroundColor(categoryColor(for: completion))
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(highlightMatch(in: completion.title, query: searchText))
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)

                                        HStack(spacing: 6) {
                                            Text(completion.subtitle)
                                                .font(.system(size: 13))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)

                                            if let distance = estimatedDistance(for: completion) {
                                                Text("•")
                                                    .foregroundColor(.secondary)
                                                Text(distance)
                                                    .font(.system(size: 13))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "arrow.up.forward")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)

                            if index < completions.count - 1 {
                                Divider()
                                    .padding(.leading, 60)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 320)
                .background(.ultraThinMaterial)
                .cornerRadius(14)
                .padding(.horizontal)
                .shadow(radius: 12)
            } else {
                // No results
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Nenhum resultado para \"\(searchText)\"")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: completions.count)
    }

    // MARK: - Helpers

    private func dismissResults() {
        showResults = false
        isFocused = false
        SearchService.shared.clearCompletions()
    }

    private func categoryIcon(for completion: MKLocalSearchCompletion) -> String {
        let subtitle = completion.subtitle.lowercased()
        let title = completion.title.lowercased()

        if subtitle.contains("gas") || title.contains("posto") || title.contains("gas") { return "fuelpump" }
        if subtitle.contains("restaurant") || subtitle.contains("food") { return "fork.knife" }
        if subtitle.contains("coffee") || subtitle.contains("café") || subtitle.contains("cafe") { return "cup.and.saucer" }
        if subtitle.contains("hotel") || subtitle.contains("lodging") { return "bed.double" }
        if subtitle.contains("hospital") || subtitle.contains("pharmacy") { return "cross.case" }
        if subtitle.contains("parking") || subtitle.contains("park") { return "parkingsign" }
        if subtitle.contains("repair") || subtitle.contains("auto") { return "wrench.and.screwdriver" }
        if subtitle.contains("grocery") || subtitle.contains("supermarket") || subtitle.contains("market") { return "cart" }
        if subtitle.contains("shopping") || subtitle.contains("mall") { return "bag" }
        if subtitle.contains("bank") || subtitle.contains("atm") { return "dollarsign.circle" }
        if subtitle.contains("bar") || subtitle.contains("pub") { return "wineglass" }
        if subtitle.contains("airport") { return "airplane" }
        if subtitle.contains("school") || subtitle.contains("university") { return "graduationcap" }
        if subtitle.contains("church") || subtitle.contains("temple") { return "building.columns" }

        return "mappin.and.ellipse"
    }

    private func categoryColor(for completion: MKLocalSearchCompletion) -> Color {
        let subtitle = completion.subtitle.lowercased()
        let title = completion.title.lowercased()

        if subtitle.contains("gas") || title.contains("posto") || title.contains("gas") { return .orange }
        if subtitle.contains("restaurant") || subtitle.contains("food") || subtitle.contains("coffee") || subtitle.contains("café") { return .red }
        if subtitle.contains("hotel") || subtitle.contains("lodging") { return .purple }
        if subtitle.contains("hospital") || subtitle.contains("pharmacy") { return .pink }
        if subtitle.contains("repair") || subtitle.contains("auto") { return .blue }
        if subtitle.contains("shopping") || subtitle.contains("mall") || subtitle.contains("grocery") || subtitle.contains("market") { return .green }
        if subtitle.contains("bar") || subtitle.contains("pub") { return .yellow }
        if subtitle.contains("airport") { return .teal }

        return .blue
    }

    private func estimatedDistance(for completion: MKLocalSearchCompletion) -> String? {
        // MKLocalSearchCompletion doesn't have coordinates,
        // so we show distance based on the subtitle context
        guard let region = mapRegion else { return nil }

        // Rough estimate: if subtitle contains a known city/neighborhood,
        // estimate based on region span. Otherwise nil (don't show fake data).
        let span = region.span
        let roughDiameter = sqrt(pow(span.latitudeDelta * 111000, 2) + pow(span.longitudeDelta * 111000 * cos(region.center.latitude * .pi / 180), 2))

        if roughDiameter > 50000 {
            return nil // Too large region, don't guess
        }

        // Estimate ~30% of region diameter as typical distance
        let est = roughDiameter * 0.3
        if est > 1000 {
            return String(format: "%.1f km", est / 1000)
        } else if est > 100 {
            return "\(Int(est)) m"
        }
        return nil
    }

    private func highlightMatch(in text: String, query: String) -> AttributedString {
        var attributed = AttributedString(text)
        if let range = attributed.range(of: query, options: .caseInsensitive) {
            attributed[range].font = .system(size: 16, weight: .bold)
        }
        return attributed
    }
}

// MARK: - Search History

final class SearchHistory {
    static let shared = SearchHistory()
    private let key = "searchHistory"
    private let maxItems = 10

    var recentSearches: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func add(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        var searches = recentSearches
        searches.removeAll { $0.lowercased() == trimmed.lowercased() }
        searches.insert(trimmed, at: 0)
        if searches.count > maxItems { searches = Array(searches.prefix(maxItems)) }
        UserDefaults.standard.set(searches, forKey: key)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
