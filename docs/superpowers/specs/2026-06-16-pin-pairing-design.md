# PIN Pairing Flow — Design Spec

**Date:** 2026-06-16
**Branch:** `v2/mesh-maplibre-ferrostar`
**Constraints:** 1 iPhone disponível para teste (lado líder)

## Goal

Leader creates a ride, generates a 4-digit PIN, advertises via BLE mesh, and waits for followers to join. Testable with a single iPhone.

## Data Model

### WawaOntology types used

- `RideEvent` — the ride (id, name, startDate, location, rideType, visibility, meshGroupId, participants, status)
- `Profile` — the leader's identity (PeerID)
- `AnnouncePayload` — BLE broadcast (nickname, groupID, visibility)
- `BitchatPacket` — wire format via BinaryProtocol v2

### State machine

```
idle → RideEvent(status: .proposed) → BLE advertising → waiting
                                              ↓
                                         follower joins (future)
                                              ↓
                                         RideEvent(status: .active) → GPS + map
```

## UI Flow

### Screen 1: CreateRideView
- Text field: ride name (default: "Sunday Ride")
- Location: auto-detected from GPS
- Button: "Criar Passeio"
- Action: generates PIN, creates RideEvent, starts BLE advertising

### Screen 2: WaitingView
- Large PIN display (4 digits, high contrast for sunlight)
- Animated "waiting" indicator
- Connected rider count
- "Partiu!" button (disabled until ≥1 rider connected — future)

## Files

| Action | File | Purpose |
|--------|------|---------|
| Create | `Sources/WawaRideApp/Views/CreateRideView.swift` | Ride creation screen |
| Create | `Sources/WawaRideApp/Views/WaitingView.swift` | Waiting for riders screen |
| Create | `Sources/WawaRideApp/ViewModels/RideState.swift` | Ride lifecycle state management |
| Modify | `Sources/WawaRideApp/WawaRideApp.swift` | Wire new views |
| Modify | `Sources/WawaRideApp/Views/RideMainView.swift` | Add flow transition |

## BLE Payload

The leader broadcasts an announce packet every 4 seconds:

```swift
let announce = AnnouncePayload(nickname: "Wagner", groupID: groupID, visibility: .groupOnly)
let json = JSONEncoder().encode(announce)
let packet = BitchatPacket(type: MessageType.announce.rawValue, ...)
mesh.broadcast(packet)
```

The groupID embeds the ride identity — followers validate the PIN against it.

## Verification

1. Build and run on 1 iPhone
2. Tap "Criar Passeio"
3. Verify PIN displayed, BLE advertising starts
4. Verify log shows BLE advertising active
5. Map opens in background (HUD shows peer count = 0)
