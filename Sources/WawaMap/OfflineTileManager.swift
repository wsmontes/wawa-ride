import Foundation
import MapLibre

/// Manages offline PMTiles/MBTiles for regional maps.
///
/// Tile generation pipeline (all tools are open-source):
/// 1. **Planetiler** generates regional basemap from OSM → .pmtiles
///    Reference: https://github.com/onthegomap/planetiler (Apache-2, 2.1k stars)
///    Command: `planetiler --area=brazil --output=brazil-sudeste.pmtiles`
///
/// 2. **Tippecanoe** converts custom GeoJSON overlays → .pmtiles
///    Reference: https://github.com/felt/tippecanoe (BSD-2, 1.5k stars)
///    Command: `tippecanoe -zg -o routes.pmtiles routes.geojson`
///
/// 3. **pmtiles CLI** extracts sub-regions from larger archives
///    Reference: https://github.com/protomaps/go-pmtiles
///    Command: `pmtiles extract planet.pmtiles sp.pmtiles --bbox=-47,-24,-45,-23`
///
/// PMTiles format (vs MBTiles):
/// - Single flat binary file (not SQLite) — optimized for HTTP range requests
/// - 10-15% smaller than equivalent MBTiles
/// - MapLibre Native reads via `pmtiles://file:///path/to/file.pmtiles`
/// - No tile server needed — file IS the database
/// Reference: https://github.com/protomaps/PMTiles (BSD-3, 2.9k stars)
///
/// Size estimates for Brazil:
/// - Full country (z0-z14): ~2-4 GB
/// - State of São Paulo: ~200-500 MB
/// - City (São Paulo metro): ~50-150 MB
/// - Single ride route corridor: ~5-20 MB
///
/// MapLibre PMTiles support:
/// Added in MapLibre Native v6.10.0+. Use `pmtiles://` protocol prefix.
/// For local files: `"url": "pmtiles://file:///path/to/basemap.pmtiles"`
/// Reference: MapLibre Android docs (iOS shares same style spec engine)
///
/// Pre-built basemaps available from Protomaps (ODbL, global coverage):
/// https://docs.protomaps.com/basemaps/downloads
/// https://github.com/protomaps/basemaps
public final class OfflineTileManager: ObservableObject {
    @Published public var availableRegions: [TileRegion] = []

    public struct TileRegion: Identifiable {
        public let id: String
        public let name: String
        public let fileURL: URL
        public let sizeBytes: UInt64
    }

    private let tilesDir: URL

    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        tilesDir = docs.appendingPathComponent("tiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: tilesDir, withIntermediateDirectories: true)
        refresh()
    }

    /// Generate a minimal style.json that references a local PMTiles file.
    /// This style is passed to MapLibre's `styleURL` parameter.
    ///
    /// For production, use Protomaps' style generator for full layer definitions:
    /// https://docs.protomaps.com/basemaps/maplibre
    public func localStyleURL(for region: TileRegion) -> URL? {
        let style: [String: Any] = [
            "version": 8,
            "name": "Wawa Ride Offline",
            "sources": ["openmaptiles": [
                "type": "vector",
                "url": "pmtiles://\(region.fileURL.path)"
            ]],
            "layers": [
                ["id": "background", "type": "background", "paint": ["background-color": "#f8f4f0"]],
                ["id": "road", "type": "line", "source": "openmaptiles", "source-layer": "transportation",
                 "paint": ["line-color": "#ffffff", "line-width": 1.5]]
            ]
        ]
        let jsonURL = tilesDir.appendingPathComponent("\(region.id)-style.json")
        if let data = try? JSONSerialization.data(withJSONObject: style) {
            try? data.write(to: jsonURL)
            return jsonURL
        }
        return nil
    }

    /// Refresh available regions from the tiles directory.
    public func refresh() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: tilesDir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        availableRegions = files
            .filter { $0.pathExtension == "pmtiles" || $0.pathExtension == "mbtiles" }
            .compactMap { url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let name = url.deletingPathExtension().lastPathComponent
                return TileRegion(id: name, name: name, fileURL: url, sizeBytes: UInt64(size))
            }
    }

    /// Import a PMTiles file (e.g., after downloading from server or AirDrop).
    public func importTiles(from source: URL, name: String) throws {
        let dest = tilesDir.appendingPathComponent("\(name).pmtiles")
        try FileManager.default.copyItem(at: source, to: dest)
        refresh()
    }
}
