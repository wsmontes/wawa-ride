import Foundation
import MapKit

// MARK: - Search Service

/// Address and place search using MKLocalSearch and MKLocalSearchCompleter.
/// Standard iOS APIs — no custom search, no reinvention.

@MainActor
final class SearchService: NSObject, ObservableObject {
    static let shared = SearchService()

    private let completer = MKLocalSearchCompleter()
    private var activeSearch: MKLocalSearch?

    @Published var completions: [MKLocalSearchCompletion] = []
    @Published var searchResults: [MKMapItem] = []
    @Published var isSearching = false

    private override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest, .query]
    }

    // MARK: - Autocomplete

    func searchCompletions(query: String, region: MKCoordinateRegion? = nil) {
        completer.queryFragment = query
        if let region {
            completer.region = region
        }
    }

    func clearCompletions() {
        completions = []
        completer.queryFragment = ""
    }

    // MARK: - Search

    func search(query: String, region: MKCoordinateRegion? = nil) async throws -> [MKMapItem] {
        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let region {
            request.region = region
        }

        let search = MKLocalSearch(request: request)
        activeSearch = search

        let response = try await search.start()
        searchResults = response.mapItems
        return response.mapItems
    }

    func search(completion: MKLocalSearchCompletion) async throws -> [MKMapItem] {
        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        activeSearch = search

        let response = try await search.start()
        searchResults = response.mapItems
        return response.mapItems
    }

    func cancelSearch() {
        activeSearch?.cancel()
        activeSearch = nil
        isSearching = false
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension SearchService: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("🔍 Search completer error: \(error.localizedDescription)")
    }
}
