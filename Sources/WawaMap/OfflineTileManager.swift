import Foundation
import MapCache

/// Offline tile caching via MapCache.
/// Tiles stored in a single SQLite file. First use downloads; subsequent loads from cache.
public final class OfflineTileManager: ObservableObject {
    public init() {}

    public func makeCache() -> MapCache {
        var config = MapCacheConfig()
        config.cacheName = "WawaMapCache"
        config.capacity = 100 * 1024 * 1024  // 100 MB
        return MapCache(withConfig: config)
    }
}
