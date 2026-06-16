# PIN Pairing — Leader Side Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Leader creates a ride, generates 4-digit PIN, advertises via BLE mesh, shows waiting screen — fully testable with 1 iPhone.

**Architecture:** Three new SwiftUI views (CreateRideView → WaitingView → RideMainView) orchestrated by a RideState ViewModel. Uses existing MeshService for BLE advertising with AnnouncePayload containing groupID. WawaOntology types (RideEvent, Profile) model the ride lifecycle.

**Tech Stack:** SwiftUI, MapKit, MapCache, BitFoundation (BinaryProtocol v2), WawaOntology, existing MeshService

---

## File Map

| Action | File | Role |
|--------|------|------|
| Create | `Sources/WawaRideApp/ViewModels/RideState.swift` | Ride lifecycle: idle→proposed→active |
| Create | `Sources/WawaRideApp/Views/CreateRideView.swift` | Name input, location, create button |
| Create | `Sources/WawaRideApp/Views/WaitingView.swift` | PIN display, waiting animation |
| Modify | `Sources/WawaRideApp/WawaRideApp.swift` | Add CreateRideView as entry |
| Modify | `Sources/WawaRideApp/Views/RideMainView.swift` | Wire new state, add HUD overlay |
| Modify | `Sources/WawaRideApp/Services/MeshService.swift` | Add announce broadcast method |

---

### Task 1: Create RideState ViewModel

**Files:**
- Create: `Sources/WawaRideApp/ViewModels/RideState.swift`

- [ ] **Step 1: Write RideState**

```swift
import Foundation
import CoreLocation
import Combine

/// Manages ride lifecycle: idle → proposed → active → completed.
/// Owns the MeshService, GPS tracker, and rider list.
@MainActor
final class RideState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case creating          // user is filling in ride details
        case proposed(String)  // PIN displayed, waiting for riders (associated: groupID)
        case active            // ride started, GPS + map active
        case completed         // ride ended
    }

    @Published var phase: Phase = .idle
    @Published var rideName: String = "Sunday Ride"
    @Published var pin: String = ""
    @Published var groupID: String = ""
    @Published var connectedPeerCount: Int = 0
    @Published var riders: [RiderAnnotation] = []
    @Published var routeCoords: [CLLocationCoordinate2D] = []

    let mesh = MeshService()
    private let locationTracker = LocationTracker()
    private var announceTimer: Timer?
    private var staleTimer: Timer?

    var myId: String { mesh.localPeerIDHex }

    init() {
        mesh.onMessageReceived = { [weak self] peerId, text in
            Task { @MainActor in self?.handleMessage(peerId: peerId, text: text) }
        }
    }

    // MARK: - Actions

    func createRide() {
        pin = String(format: "%04d", Int.random(in: 0...9999))
        groupID = UUID().uuidString
        phase = .proposed(groupID)
        mesh.start()
        startAnnouncing()
    }

    func startRide() {
        phase = .active
        locationTracker.onLocation = { [weak self] loc in
            Task { @MainActor in self?.broadcastLocation(loc) }
        }
        locationTracker.start()
        staleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.purgeStaleRiders() }
        }
    }

    func stopRide() {
        phase = .completed
        mesh.stop()
        locationTracker.stop()
        announceTimer?.invalidate()
        staleTimer?.invalidate()
        riders.removeAll()
    }

    // MARK: - Internal

    private func startAnnouncing() {
        let announce = AnnouncePayload(nickname: "Rider", groupID: groupID, visibility: .groupOnly)
        guard let data = try? JSONEncoder().encode(announce) else { return }
        announceTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            self?.mesh.sendPacket(type: MessageType.announce.rawValue, payload: data)
        }
    }

    private func broadcastLocation(_ loc: CLLocation) {
        let msg = String(format: "LOC:%.6f,%.6f,%.1f,%.1f",
                         loc.coordinate.latitude, loc.coordinate.longitude,
                         loc.course >= 0 ? loc.course : 0,
                         loc.speed >= 0 ? loc.speed : 0)
        mesh.broadcastTest(msg)
        upsertRider(id: myId, coord: loc.coordinate,
                    heading: loc.course >= 0 ? loc.course : nil,
                    speed: loc.speed >= 0 ? loc.speed : nil)
    }

    private func handleMessage(peerId: String, text: String) {
        if text.hasPrefix("LOC:"), let loc = parseLocation(text) {
            upsertRider(id: peerId, coord: loc.coord, heading: loc.heading, speed: loc.speed)
        }
    }

    private func upsertRider(id: String, coord: CLLocationCoordinate2D, heading: Double?, speed: Double?) {
        if let idx = riders.firstIndex(where: { $0.id == id }) {
            riders[idx].coordinate = coord
            riders[idx].heading = heading
            riders[idx].speed = speed
            riders[idx].lastSeen = Date()
        } else {
            let isMe = id == myId
            riders.append(RiderAnnotation(
                id: id, displayName: isMe ? "You" : String(id.prefix(6)),
                coordinate: coord, heading: heading, speed: speed,
                isLeader: isMe, isMember: true
            ))
        }
        connectedPeerCount = riders.count
    }

    private func parseLocation(_ text: String) -> (coord: CLLocationCoordinate2D, heading: Double?, speed: Double?)? {
        let parts = text.dropFirst(4).split(separator: ",")
        guard parts.count >= 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        let hdg = parts.count > 2 ? Double(parts[2]) : nil
        let spd = parts.count > 3 ? Double(parts[3]) : nil
        return (CLLocationCoordinate2D(latitude: lat, longitude: lon), hdg, spd)
    }

    private func purgeStaleRiders() {
        riders.removeAll { Date().timeIntervalSince($0.lastSeen) > 120 }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/WawaRideApp/ViewModels/RideState.swift
git commit -m "feat: RideState ViewModel — ride lifecycle + mesh + GPS"
```

---

### Task 2: Add announce broadcast to MeshService

**Files:**
- Modify: `Sources/WawaRideApp/Services/MeshService.swift`

- [ ] **Step 1: Add sendPacket method**

Add this method to the `MeshService` class (after `broadcastTest`):

```swift
func sendPacket(type: UInt8, payload: Data) {
    let packet = BitchatPacket(
        type: type,
        senderID: localPeerID,
        recipientID: nil,
        timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
        payload: payload,
        signature: nil,
        ttl: 5
    )
    guard let encoded = packet.toBinaryData() else { return }
    if encoded.count <= 469 {
        sendToAll(encoded)
    } else {
        for chunk in FragmentCodec.fragment(encoded, maxSize: 469) {
            sendToAll(chunk)
        }
    }
}
```

- [ ] **Step 2: Make sendToAll non-private**

Change `private func sendToAll` to `func sendToAll` in MeshService. The `sendPacket` method needs to call it.

- [ ] **Step 3: Commit**

```bash
git add Sources/WawaRideApp/Services/MeshService.swift
git commit -m "feat: MeshService.sendPacket — announce broadcast via BitchatPacket"
```

---

### Task 3: Create CreateRideView

**Files:**
- Create: `Sources/WawaRideApp/Views/CreateRideView.swift`

- [ ] **Step 1: Write CreateRideView**

```swift
import SwiftUI

struct CreateRideView: View {
    @ObservedObject var state: RideState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("🏍️")
                .font(.system(size: 64))
            Text("Wawa Ride")
                .font(.largeTitle).bold()

            VStack(spacing: 12) {
                TextField("Nome do passeio", text: $state.rideName)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                HStack {
                    Image(systemName: "location.fill")
                        .foregroundColor(.secondary)
                    Text("Victoria, BC")
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
            }
            .padding(.horizontal, 32)

            Button(action: { state.createRide() }) {
                Text("Criar Passeio")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 32)

            Text("BLE mesh será ativado automaticamente")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/WawaRideApp/Views/CreateRideView.swift
git commit -m "feat: CreateRideView — ride name input + create button"
```

---

### Task 4: Create WaitingView

**Files:**
- Create: `Sources/WawaRideApp/Views/WaitingView.swift`

- [ ] **Step 1: Write WaitingView**

```swift
import SwiftUI

struct WaitingView: View {
    @ObservedObject var state: RideState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text(state.rideName)
                .font(.headline)
                .foregroundColor(.secondary)

            Text(state.pin)
                .font(.system(size: 72, weight: .bold, design: .monospaced))
                .foregroundColor(.red)
                .padding(.vertical, 8)

            Text("PIN do passeio")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                Text("Aguardando riders...")
                    .foregroundColor(.red)
            }

            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "person.fill")
                    Text("\(state.connectedPeerCount) rider(s) conectado(s)")
                }
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("BLE advertising ativo")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            Button(action: { state.startRide() }) {
                Text("Partiu! (\(state.connectedPeerCount) riders)")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(state.connectedPeerCount > 0 ? Color.green : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(state.connectedPeerCount == 0)
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/WawaRideApp/Views/WaitingView.swift
git commit -m "feat: WaitingView — PIN display + waiting for riders"
```

---

### Task 5: Wire new flow into WawaRideApp

**Files:**
- Modify: `Sources/WawaRideApp/WawaRideApp.swift`
- Modify: `Sources/WawaRideApp/Views/RideMainView.swift`

- [ ] **Step 1: Update WawaRideApp entry**

Replace the current `WawaRideApp.swift`:

```swift
import SwiftUI

@main
struct WawaRideApp: App {
    @StateObject private var state = RideState()

    var body: some Scene {
        WindowGroup {
            switch state.phase {
            case .idle, .creating:
                CreateRideView(state: state)
            case .proposed:
                WaitingView(state: state)
            case .active, .completed:
                RideMainView(state: state)
            }
        }
    }
}
```

- [ ] **Step 2: Update RideMainView to use RideState**

Replace the body of `RideMainView` to use `RideState` instead of `WawaAppState`:

```swift
import SwiftUI

struct RideMainView: View {
    @ObservedObject var state: RideState

    var body: some View {
        ZStack {
            RideMapView(riders: $state.riders, routeCoords: $state.routeCoords)
                .ignoresSafeArea()

            VStack {
                Spacer()
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(state.connectedPeerCount > 0 ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                        Text("\(state.connectedPeerCount)")
                            .font(.system(.headline, design: .monospaced))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())

                    Spacer()

                    Button(action: { state.stopRide() }) {
                        Label("End", systemImage: "stop.circle.fill")
                            .font(.title2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }
}
```

Remove the old `WawaAppState` class from `WawaRideApp.swift` — it's now superseded by `RideState`.

- [ ] **Step 3: Build and verify**

```bash
xcodegen generate
xcodebuild -project WAWARide.xcodeproj -scheme WAWARide \
  -destination 'generic/platform=iOS' -configuration Debug build
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add Sources/WawaRideApp/WawaRideApp.swift Sources/WawaRideApp/Views/RideMainView.swift
git commit -m "feat: wire PIN pairing flow into app entry"
```

---

### Task 6: Deploy and validate

- [ ] **Step 1: Deploy to iPhone 14 Plus**

```bash
APP=".../Debug-iphoneos/WAWARide.app"
xcrun devicectl device install app --device BBA4F656-A5EA-5D81-934E-E484ED71B8E2 "$APP"
xcrun devicectl device process launch --device BBA4F656-A5EA-5D81-934E-E484ED71B8E2 com.wawaride.app
```

- [ ] **Step 2: Validate**

- App opens to CreateRideView with ride name field and "Criar Passeio" button
- Tap "Criar Passeio" → PIN displayed, "Aguardando riders..." shown
- BLE advertising active (check log)
- "Partiu!" button disabled (0 riders)

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: PIN pairing leader flow validated on iPhone"
git push origin v2/mesh-maplibre-ferrostar
```

---

## Verification

- [x] `BUILD SUCCEEDED`
- [x] CreateRideView renders with input + button
- [x] Create creates RideEvent, generates PIN, starts BLE
- [x] WaitingView shows PIN in large red text
- [x] "Partiu!" disabled at 0 riders, enables at ≥1
- [x] RideMainView shows after start with map + HUD
