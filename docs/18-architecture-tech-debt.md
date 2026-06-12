# Architecture Tech Debt Log

**Audit date:** June 2026 | **Auditor persona:** Tech Lead / Software Architect

---

## 🔴 High — Dead Code (3 files, 1050 lines)

Three view files have **zero external references** — never instantiated, never navigated to:

| File | Lines | Notes |
|------|-------|-------|
| `ExploreMapView.swift` | 460 | Duplicated search/map UI. Replaced by UnifiedMapView. |
| `JoinRideView.swift` | 237 | Duplicated ride creation + mesh join. Replaced by UnifiedMapView's `nearbyRidesBanner`. |
| `RideActiveView.swift` | 353 | Duplicated mesh handler + ride session. Replaced by UnifiedMapView. |

**Action:** Delete these 3 files. Their logic is fully covered by `UnifiedMapView`.

---

## 🔴 High — God View: UnifiedMapView (1390 lines)

One file contains 9 distinct responsibilities:

| Concern | Lines | Should be |
|---------|-------|-----------|
| View hierarchy (ZStack overlays) | ~200 | `UnifiedMapView.swift` |
| Sheet management | ~40 | `UnifiedMapView.swift` |
| BLE banner + rider-joined banner | ~100 | `NearbyRidesBanner.swift` |
| Hazard undo logic | ~30 | `HazardUndoOverlay.swift` |
| Ride session + location sharing + mesh handler | ~150 | `RideSessionManager.swift` |
| NavigationHUD (sub-struct) | ~80 | `NavigationHUD.swift` |
| RiderHUD (sub-struct) | ~180 | `RiderHUD.swift` |
| UnifiedMapUIKit + Coordinator | ~200 | `UnifiedMapUIKit.swift` |
| TypedPointAnnotation + PinType | ~15 | `TypedPointAnnotation.swift` |

**Action:** Extract sub-views and the Coordinator into separate files. Keep `UnifiedMapView` as the orchestrator (~200 lines).

---

## 🟡 Medium — Ride creation duplicated 3x

`CreateRideView`, `JoinRideView`, and `ExploreMapView` each contain their own ride creation flow:
- All three call `MeshService.shared.startAdvertising()`
- All three call `RoomService.shared.createDefaultRooms()`
- All three set `AppState.shared.currentRideId`
- Only `CreateRideView` generates a rideCode (the other two were missing it — fixed in `0b7fb7e` for JoinRideView)

**Action:** After deleting dead code, consider extracting `RideCreationService` to centralize:
```swift
RideCreationService.create(name:rideCode:route:)
```

---

## 🟡 Medium — Singleton coupling

20+ references to `AppState.shared` across services. Every service directly depends on the global singleton, making unit testing impossible.

| Singleton | External references |
|-----------|-------------------|
| `AppState.shared` | 20+ |
| `MeshService.shared` | 15+ |
| `LocationService.shared` | 10+ |
| `LocalStore.shared` | 20+ |

**Action:** Introduce protocol-based dependency injection for critical services:
```swift
protocol RideStateProviding {
    var currentRideId: String? { get }
}
// AppState : RideStateProviding
// MeshService(rideState: RideStateProviding)
```

---

## 🟢 Low — 110 silent `try?` calls

Error logging added to `LocalStore.saveRoute()` in `e960c24`. Pattern should be extended to remaining critical paths.

**Action:** Extend `logDBError()` pattern to `saveRideSummary`, `saveVoiceMessage`, `saveRoom`.

---

## Summary

| Priority | Items | Effort |
|----------|-------|--------|
| 🔴 Delete dead code | 3 files | 5 min |
| 🔴 Extract God View | 6 extractions | 2-3 hours |
| 🟡 Centralize ride creation | 1 service | 1 hour |
| 🟡 DI for singletons | Protocol layer | 2-3 hours |
| 🟢 Extend error logging | 3 methods | 30 min |

**Risk of NOT addressing:** Dead code causes confusion for new developers. God View makes bug fixes risky (changes in one area break another). Singleton coupling prevents testing. All three should be addressed before adding a 2nd developer to the project.
