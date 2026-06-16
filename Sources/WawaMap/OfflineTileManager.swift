import Foundation
import MapLibre

/// Map tile source. Currently uses OSM raster (online, proven to work).
/// PMTiles support in MapLibre iOS 6.27.0 xcframework is broken.
/// TODO: switch to MBTiles for offline support.
public final class OfflineTileManager: ObservableObject {
    public init() {}

    public func makeStyleURL() -> URL {
        let style: [String: Any] = [
            "version": 8,
            "name": "Wawa Ride",
            "sources": [
                "osm": [
                    "type": "raster",
                    "tiles": ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
                    "tileSize": 256,
                    "attribution": "© OpenStreetMap contributors"
                ] as [String: Any]
            ],
            "layers": [
                ["id": "osm", "type": "raster", "source": "osm"]
            ]
        ]
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("wawa-osm.json")
        if let d = try? JSONSerialization.data(withJSONObject: style, options: .sortedKeys) {
            try? d.write(to: out, options: .atomic)
        }
        return out
    }
}
