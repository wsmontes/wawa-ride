import Foundation
import MapLibre

/// Downloads and manages offline map tile packs.
public final class OfflineTileManager: ObservableObject {
    @Published public var downloadProgress: Float?
    @Published public var downloadedRegions: [String] = []
    private let styleURL: URL

    public init(styleURL: URL) {
        self.styleURL = styleURL
        loadExisting()
        NotificationCenter.default.addObserver(forName: .MLNOfflinePackProgressChanged, object: nil, queue: .main) { [weak self] n in
            guard let pack = n.object as? MLNOfflinePack else { return }
            let p = pack.progress
            self?.downloadProgress = Float(p.countOfResourcesCompleted) / max(Float(p.countOfResourcesExpected), 1)
            if pack.state == .complete { self?.downloadProgress = nil; self?.loadExisting() }
        }
    }

    public func download(name: String, bounds: MLNCoordinateBounds, minZoom: Double = 8, maxZoom: Double = 15) {
        let region = MLNTilePyramidOfflineRegion(styleURL: styleURL, bounds: bounds, fromZoomLevel: minZoom, toZoomLevel: maxZoom)
        let ctx = (try? JSONEncoder().encode(["name": name])) ?? Data()
        MLNOfflineStorage.shared.addPack(for: region, withContext: ctx) { pack, _ in pack?.resume() }
        downloadProgress = 0
    }

    public func removeAll() {
        for pack in MLNOfflineStorage.shared.packs ?? [] {
            MLNOfflineStorage.shared.removePack(pack) { _ in }
        }
        downloadedRegions.removeAll()
    }

    private func loadExisting() {
        downloadedRegions = (MLNOfflineStorage.shared.packs ?? []).compactMap { pack in
            guard let meta = try? JSONDecoder().decode([String: String].self, from: pack.context) else { return nil }
            return meta["name"]
        }
    }
}
