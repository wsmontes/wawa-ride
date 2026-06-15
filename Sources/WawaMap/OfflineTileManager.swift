import Foundation
import MapLibre

/// Manages offline PMTiles/MBTiles for regional maps.
/// Pipeline: Planetiler generates .pmtiles → bundle or download → MapLibre reads via file:// URL.
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

    /// Style JSON pointing to a local PMTiles file.
    public func localStyleURL(for region: TileRegion) -> URL? {
        // Generate a minimal style.json that references the local PMTiles
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

    /// Import a PMTiles file from a temporary location (e.g., after download).
    public func importTiles(from source: URL, name: String) throws {
        let dest = tilesDir.appendingPathComponent("\(name).pmtiles")
        try FileManager.default.copyItem(at: source, to: dest)
        refresh()
    }
}
