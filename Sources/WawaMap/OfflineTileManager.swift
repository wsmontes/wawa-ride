import Foundation
import MapLibre

/// Manages offline PMTiles for the motorcycle ride map.
///
/// Two sources of tiles:
/// 1. **Bundled** — Victoria region PMTiles shipped with the app (~8 MB, always available)
/// 2. **Downloaded** — additional regions downloaded on-demand (future)
///
/// PMTiles is a single-file format optimized for HTTP range requests.
/// MapLibre reads it directly via `pmtiles://` protocol — no tile server needed.
/// Reference: https://github.com/protomaps/PMTiles
public final class OfflineTileManager: ObservableObject {
    @Published public var availableRegions: [TileRegion] = []

    public struct TileRegion: Identifiable {
        public let id: String
        public let name: String
        public let fileURL: URL
        public let sizeBytes: UInt64
        public let isBundled: Bool
    }

    private let tilesDir: URL

    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        tilesDir = docs.appendingPathComponent("tiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: tilesDir, withIntermediateDirectories: true)
        refresh()
    }

    // MARK: - Bundled map

    /// URL for the bundled Victoria style.json.
    ///
    /// The style references tiles at `pmtiles://Tiles/victoria.pmtiles`
    /// which resolves relative to the app bundle. MapLibre's PMTiles
    /// integration handles this transparently.
    public var bundledStyleURL: URL? {
        Bundle.main.url(forResource: "Tiles/style", withExtension: "json")
    }

    /// The bundled Victoria PMTiles region.
    public var victoriaRegion: TileRegion? {
        availableRegions.first { $0.id == "victoria" }
    }

    // MARK: - Dynamic loading

    /// Refresh available regions from tiles directory and app bundle.
    public func refresh() {
        var regions: [TileRegion] = []

        // Scan app bundle for bundled tiles
        if let bundleTiles = Bundle.main.urls(forResourcesWithExtension: "pmtiles", subdirectory: "Tiles") {
            for url in bundleTiles {
                let name = url.deletingPathExtension().lastPathComponent
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                regions.append(TileRegion(
                    id: name, name: name.capitalized, fileURL: url,
                    sizeBytes: UInt64(size), isBundled: true
                ))
            }
        }

        // Scan documents directory for downloaded tiles
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: tilesDir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        for url in files where url.pathExtension == "pmtiles" || url.pathExtension == "mbtiles" {
            let name = url.deletingPathExtension().lastPathComponent
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            // Don't duplicate if already in bundle
            if !regions.contains(where: { $0.id == name }) {
                regions.append(TileRegion(
                    id: name, name: name.capitalized, fileURL: url,
                    sizeBytes: UInt64(size), isBundled: false
                ))
            }
        }

        availableRegions = regions
    }

    /// Import a PMTiles file (e.g., after downloading or AirDrop).
    public func importTiles(from source: URL, name: String) throws {
        let dest = tilesDir.appendingPathComponent("\(name).pmtiles")
        try FileManager.default.copyItem(at: source, to: dest)
        refresh()
    }
}
