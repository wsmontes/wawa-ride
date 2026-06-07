import SwiftUI
import MapKit

// MARK: - Search Bar View

/// Search bar with autocomplete using MKLocalSearchCompleter.
/// Reusable component for both LiveMapView and RouteCreatorView.

struct SearchBarView: View {
    @Binding var searchText: String
    let completions: [MKLocalSearchCompletion]
    let isSearching: Bool
    let onSelectCompletion: (MKLocalSearchCompletion) -> Void
    let onSubmit: () -> Void

    @State private var showCompletions = false

    var body: some View {
        VStack(spacing: 0) {
            // Search input
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Buscar lugar ou endereço", text: $searchText)
                        .textFieldStyle(.plain)
                        .foregroundColor(.primary)
                        .onSubmit {
                            showCompletions = false
                            onSubmit()
                        }
                        .onChange(of: searchText) { _, newValue in
                            showCompletions = !newValue.isEmpty
                            if !newValue.isEmpty {
                                SearchService.shared.searchCompletions(query: newValue)
                            } else {
                                SearchService.shared.clearCompletions()
                            }
                        }

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            showCompletions = false
                            SearchService.shared.clearCompletions()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.systemGray5))
                .cornerRadius(10)

                if isSearching {
                    ProgressView()
                        .padding(.trailing, 8)
                }
            }
            .padding(.horizontal)

            // Autocomplete results
            if showCompletions && !completions.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(completions.enumerated()), id: \.offset) { _, completion in
                            Button {
                                searchText = completion.title
                                showCompletions = false
                                SearchService.shared.clearCompletions()
                                onSelectCompletion(completion)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(completion.title)
                                        .font(.body)
                                        .foregroundColor(.primary)

                                    Text(completion.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            if completion != completions.last {
                                Divider()
                                    .padding(.leading)
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(Color(.systemGray6).opacity(0.95))
                .cornerRadius(12)
                .padding(.horizontal)
                .shadow(radius: 8)
            }
        }
    }
}
