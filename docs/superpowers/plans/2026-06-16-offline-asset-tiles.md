# MapLibre Offline Maps via asset:// Scheme

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace OSM online raster tiles with fully offline vector tiles using MapLibre's built-in `asset://` scheme.

**Architecture:** Extract gzip-compressed PBF tiles from MBTiles into `z/x/y.pbf` directory tree on disk, create a local style.json referencing them via `asset://`, bundle both in the app via xcodegen resources. MapLibre reads tiles directly from the app bundle — zero network, zero codec dependencies.

**Tech Stack:** MapLibre Native iOS (SPM v6.27.0), MBTiles (converted from Protomaps PMTiles), Protomaps v4 tile schema.

---

## File Structure

```
Sources/WawaRideApp/Resources/
├── Victoria/                    ← NEW: extracted tiles (~16 MB, 85K .pbf files)
│   └── {z}/{x}/{y}.pbf
├── Tiles/
│   ├── victoria.pmtiles         ← source (keep for regeneration)
│   ├── victoria.mbtiles         ← intermediate (keep for extraction)
│   └── style-template.json      ← EXISTING (69 layers, Protomaps light)
├── Assets.xcassets/             ← EXISTING
└── offline-style.json           ← NEW: style using asset:// scheme

Sources/WawaMap/
├── OfflineTileManager.swift     ← MODIFY: add asset:// style support
└── RideMapView.swift            ← MODIFY: use offline style

project.yml                      ← MODIFY: bundle Victoria/ directory
```

---

### Task 1: Extract compressed tiles from MBTiles to directory

**Files:**
- Create: `Sources/WawaRideApp/Resources/Victoria/` (directory tree with `.pbf` files)

- [ ] **Step 1: Clean any previous extraction**

```bash
rm -rf Sources/WawaRideApp/Resources/Victoria
mkdir -p Sources/WawaRideApp/Resources/Victoria
```

- [ ] **Step 2: Extract tiles keeping gzip compression**

MBTiles stores tile_data blobs that may be gzip-compressed or raw. The `tile-join` conversion from PMTiles preserves compression. Extract as-is:

```bash
node -e "
const Database = require('better-sqlite3');
const db = new Database('Sources/WawaRideApp/Resources/Tiles/victoria.mbtiles', {readonly: true});
const rows = db.prepare('SELECT zoom_level, tile_column, tile_row, tile_data FROM tiles').all();
const fs = require('fs');

let count = 0, totalBytes = 0;
for (const row of rows) {
  // MBTiles uses TMS y-axis; convert to XYZ
  const tmsY = (1 << row.zoom_level) - 1 - row.tile_row;
  const dir = 'Sources/WawaRideApp/Resources/Victoria/' + row.zoom_level + '/' + row.tile_column;
  fs.mkdirSync(dir, {recursive: true});
  // Write raw blob (already gzip-compressed from Protomaps pipeline)
  fs.writeFileSync(dir + '/' + tmsY + '.pbf', row.tile_data);
  totalBytes += row.tile_data.length;
  count++;
}
console.log(count + ' tiles, ' + (totalBytes / 1024 / 1024).toFixed(1) + ' MB');
"
```

Run: `node -e "..."`  
Expected: `85086 tiles, ~16 MB`

- [ ] **Step 3: Verify directory structure**

```bash
ls Sources/WawaRideApp/Resources/Victoria/0/0/0.pbf && echo "OK"
du -sh Sources/WawaRideApp/Resources/Victoria/
```

Expected: `0.pbf exists`, size ~16-18 MB

- [ ] **Step 4: Commit extracted tiles**

```bash
git add Sources/WawaRideApp/Resources/Victoria/
git commit -m "feat: extract Victoria MBTiles to z/x/y.pbf tiles (16 MB, 85K files)"
```

---

### Task 2: Create offline style.json using asset:// scheme

**Files:**
- Create: `Sources/WawaRideApp/Resources/offline-style.json`

- [ ] **Step 1: Create the offline style JSON**

The `asset://` scheme resolves to the app bundle root. Tiles are at `Victoria/{z}/{x}/{y}.pbf` relative to the bundle. MapLibre's asset:// protocol strips the leading `asset://` and reads from the bundle.

Create `Sources/WawaRideApp/Resources/offline-style.json`:

```json
{
  "version": 8,
  "name": "Victoria Offline",
  "sources": {
    "victoria": {
      "type": "vector",
      "tiles": ["asset://Victoria/{z}/{x}/{y}.pbf"],
      "minzoom": 0,
      "maxzoom": 15
    }
  },
  "layers": [
    {
      "id": "background",
      "type": "background",
      "paint": {"background-color": "#f8f4f0"}
    },
    {
      "id": "water",
      "type": "fill",
      "source": "victoria",
      "source-layer": "water",
      "paint": {"fill-color": "#aaccdd"}
    },
    {
      "id": "roads-major",
      "type": "line",
      "source": "victoria",
      "source-layer": "roads",
      "filter": ["any", ["==", "kind", "highway"], ["==", "kind", "major_road"]],
      "paint": {"line-color": "#666666", "line-width": 2},
      "layout": {"line-cap": "round", "line-join": "round"}
    },
    {
      "id": "roads-minor",
      "type": "line",
      "source": "victoria",
      "source-layer": "roads",
      "filter": ["any", ["==", "kind", "medium_road"], ["==", "kind", "minor_road"]],
      "paint": {"line-color": "#aaaaaa", "line-width": 1}
    },
    {
      "id": "buildings",
      "type": "fill",
      "source": "victoria",
      "source-layer": "buildings",
      "paint": {"fill-color": "#d0d0d0", "fill-opacity": 0.7}
    },
    {
      "id": "landuse-park",
      "type": "fill",
      "source": "victoria",
      "source-layer": "landuse",
      "filter": ["==", "kind", "park"],
      "paint": {"fill-color": "#c8e0c0", "fill-opacity": 0.6}
    },
    {
      "id": "places",
      "type": "symbol",
      "source": "victoria",
      "source-layer": "places",
      "filter": ["any", ["==", "kind", "locality"], ["==", "kind", "neighbourhood"]],
      "layout": {"text-field": ["get", "name"], "text-size": 11},
      "paint": {"text-color": "#333333", "text-halo-color": "#ffffff", "text-halo-width": 1}
    }
  ]
}
```

Note: Layer names (`water`, `roads`, `buildings`, `landuse`, `places`) match Protomaps v4 schema as used by our PMTiles source. The `"kind"` attribute is Protomaps' field for sub-classification.

- [ ] **Step 2: Verify the JSON is valid**

```bash
python3 -c "import json; json.load(open('Sources/WawaRideApp/Resources/offline-style.json')); print('Valid JSON')"
```

- [ ] **Step 3: Commit**

```bash
git add Sources/WawaRideApp/Resources/offline-style.json
git commit -m "feat: offline style.json using asset:// scheme for Victoria tiles"
```

---

### Task 3: Update OfflineTileManager for asset:// tiles

**Files:**
- Modify: `Sources/WawaMap/OfflineTileManager.swift`

- [ ] **Step 1: Rewrite OfflineTileManager for asset:// style**

```swift
import Foundation
import MapLibre

/// Offline map using MapLibre's native asset:// scheme.
/// Tiles are bundled at Victoria/{z}/{x}/{y}.pbf, extracted from PMTiles.
/// Reference: openmaptiles-ios-demo by roblabs
public final class OfflineTileManager: ObservableObject {

    public init() {}

    /// URL for the bundled offline style JSON.
    /// Falls back to online OSM if offline style is not found.
    public var mapStyleURL: URL {
        if let local = Bundle.main.url(forResource: "offline-style", withExtension: "json") {
            return local
        }
        // Fallback: online OSM raster
        return URL(string: "https://demotiles.maplibre.org/style.json")!
    }
}
```

Delete all the old MBTiles/PMTiles URL construction code — no longer needed. The `asset://` scheme handles everything natively.

- [ ] **Step 2: Commit**

```bash
git add Sources/WawaMap/OfflineTileManager.swift
git commit -m "refactor: OfflineTileManager simplified to use asset:// offline style"
```

---

### Task 4: Update RideMapView to use offline style

**Files:**
- Modify: `Sources/WawaMap/RideMapView.swift`

- [ ] **Step 1: Update defaultStyleURL**

In `RideMapView.swift`, change the `defaultStyleURL()` method:

```swift
public static func defaultStyleURL() -> URL {
    return OfflineTileManager().mapStyleURL
}
```

This is all that changes — a one-line replacement. The existing `RideMapView` UIViewRepresentable, rider annotations, route polylines, and MapLibre delegation all stay the same.

- [ ] **Step 2: Commit**

```bash
git add Sources/WawaMap/RideMapView.swift
git commit -m "feat: RideMapView uses offline asset:// style by default"
```

---

### Task 5: Update project.yml to bundle tile directory

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Add Victoria tile directory as a resource**

In `project.yml`, add the Victoria directory to the target resources (alongside existing Assets.xcassets and Tiles):

```yaml
    resources:
      - path: Sources/WawaRideApp/Resources/Assets.xcassets
      - path: Sources/WawaRideApp/Resources/Tiles
      - path: Sources/WawaRideApp/Resources/Victoria
      - path: Sources/WawaRideApp/Resources/offline-style.json
```

xcodegen copies directory-based resources into the app bundle root. The `Victoria/` folder in the bundle root matches the `asset://Victoria/` path in the style.

- [ ] **Step 2: Regenerate Xcode project and build**

```bash
xcodegen generate
xcodebuild -project WAWARide.xcodeproj -scheme WAWARide \
  -destination 'generic/platform=iOS' -configuration Debug build
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Verify offline-style.json and Victoria/ are in the .app bundle**

```bash
ls "$APP_PATH/offline-style.json" && echo "STYLE PRESENT"
ls "$APP_PATH/Victoria/0/0/0.pbf" && echo "TILES PRESENT"
```

Expected: Both files present

- [ ] **Step 4: Commit**

```bash
git add project.yml
git commit -m "build: bundle Victoria tiles and offline style for asset://"
```

---

### Task 6: Deploy and test offline

**Devices:** iPhone 14 Plus and iPhone 15

- [ ] **Step 1: Build and install**

```bash
xcodebuild -project WAWARide.xcodeproj -scheme WAWARide \
  -destination 'generic/platform=iOS' -configuration Debug build

xcrun devicectl device install app \
  --device BBA4F656-A5EA-5D81-934E-E484ED71B8E2 \
  "$APP_PATH"

xcrun devicectl device install app \
  --device B66F5659-BCBE-5147-B7AE-A7E0F67A34D3 \
  "$APP_PATH"
```

- [ ] **Step 2: Launch both with airplane mode ON**

```bash
xcrun devicectl device process launch \
  --device BBA4F656-A5EA-5D81-934E-E484ED71B8E2 com.wawaride.app

xcrun devicectl device process launch \
  --device B66F5659-BCBE-5147-B7AE-A7E0F67A34D3 com.wawaride.app
```

- [ ] **Step 3: Verify**

- Map renders immediately (no internet needed)
- Zoom in/out works smoothly
- Street names appear (if tiles have labels)
- Both phones see each other via BLE mesh

- [ ] **Step 4: Commit final state**

```bash
git add -A && git commit -m "feat: fully offline vector maps via MapLibre asset://"
git push origin v2/mesh-maplibre-ferrostar
```

---

## Verification Checklist

- [ ] `BUILD SUCCEEDED` with offline-style.json and Victoria/ in bundle
- [ ] Map renders in airplane mode on both iPhones
- [ ] BLE mesh + GPS riders still work (unchanged)
- [ ] No regressions to existing functionality
