# Wawa Personal Ontology v0.1 — Full Definition

**Date:** 2026-06-15
**Status:** Reference document — defines all types across all phases. Scope A implements the Core subset.

## Principle

> WawaRide does not "use a social protocol."
> It produces objects compatible with the maximum number of existing social protocols.

This ontology is NOT a new world standard. It is a **profile of interoperability**: JSON-LD compatible with ActivityStreams, Schema.org, DID, and VC, with minimal `wawa:*` extensions, translatable to ActivityPub, Nostr, ATProto, and Solid.

## The Rule of Fields

```
1. ActivityStreams → first choice for social grammar
2. Schema.org → first choice for common vocabulary
3. DID → identity
4. Verifiable Credentials → claims, membership, roles
5. Nostr/ActivityPub/ATProto → transport mapping
6. wawa:* → only when nothing else covers it
```

## Protocol Map

| Concept | Wawa Field | AS2 | Schema.org | DID/VC | Nostr | ATProto |
|---------|-----------|-----|-----------|--------|-------|---------|
| Identifier | `id` | `id` | `@id` | `id` | `id` | URI/CID |
| Type | `type` array | `type` | `@type` | `type` | `kind` | `$type` |
| Author | `attributedTo` | `actor`/`attributedTo` | `author`/`creator` | `issuer` | `pubkey` | repo DID |
| Timestamp | `published`/`updated` | `published` | `datePublished`/`dateModified` | `validFrom`/`validUntil` | `created_at` | createdAt |
| Content | semantic fields | `content`/`name`/`summary` | `name`/`description` | `credentialSubject` claims | `content` | record fields |
| Object ref | `object`/`target`/`subject` | `object`/`target` | specific rels | `credentialSubject.id` | `tags` `[["e",...]]` | record ref |
| Proof | `proof` | external (HTTP sig) | external | `proof` (JOSE/LD) | `sig` | signed commit |
| Media | `attachment`/`image` | `Link`/`Image`/`Document` | `ImageObject`/`MediaObject` | related resource | tags + content | blob CID |
| Extension | `@context` + `wawa:*` | JSON-LD context | vocab | credential schema | NIPs | Lexicon |
| Versioning | `updated` + repo | `updated` | `dateModified` | — | replaceable events | commit chain |
| Visibility | `to`/`cc`/`audience` | `to`/`cc`/`audience` | — | — | `tags` `[["p",...]]` | — |

---

## All Object Types

### Identity

#### Profile

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | Wawa | `did:key:...` or `urn:wawa:peer:...` | ✓ |
| `type` | Wawa+Schema | `["Person", "wawa:Profile"]` | ✓ |
| `name` | Schema | `String?` | |
| `givenName` | Schema | `String?` | |
| `familyName` | Schema | `String?` | |
| `image` | Schema | `MediaObject?` | |
| `peerID` | Wawa | `String?` (hex, 8-byte mesh) | |
| `publicKey` | Wawa | `String?` (multibase Ed25519) | |
| `clubs` | Wawa | `[String]` (DID refs) | |
| `attributedTo` | AS2 | `String?` | |
| `published` | AS2 | `Date` | ✓ |
| `updated` | AS2 | `Date?` | |

**JSON-LD example:**
```json
{
  "@context": ["https://www.w3.org/ns/activitystreams", "https://schema.org", "https://wawa.social/ns/v1"],
  "type": ["Person", "wawa:Profile"],
  "id": "did:key:z6MkhaXgB...",
  "name": "Wagner",
  "peerID": "a1b2c3d4e5f6g7h8",
  "publicKey": "z6MkhaXgB...",
  "clubs": ["did:key:clubBrazoocas"],
  "published": "2026-06-15T09:00:00Z"
}
```

#### Organization / Club

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | Wawa | `did:key:...` or `did:web:...` | ✓ |
| `type` | Schema | `["Organization", "wawa:Club"]` | ✓ |
| `name` | Schema | `String` | ✓ |
| `description` | Schema | `String?` | |
| `image` | Schema | `MediaObject?` | |
| `url` | Schema | `String?` | |
| `members` | Wawa | `[String]` (DID refs) | |
| `admins` | Wawa | `[String]` (DID refs) | |

#### Device

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | Wawa | `did:key:...` (device sub-key) | ✓ |
| `type` | Wawa | `["wawa:Device"]` | ✓ |
| `owner` | Wawa | `String` (DID ref to Profile) | ✓ |
| `deviceName` | Wawa | `String?` | |
| `platform` | Wawa | `String?` ("iOS", "Android") | |

---

### Social

#### Post

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | AS2 | `String` | ✓ |
| `type` | AS2 | `["Note", "wawa:Post"]` | ✓ |
| `content` | AS2 | `String` | ✓ |
| `name` | AS2 | `String?` | |
| `summary` | AS2 | `String?` | |
| `inReplyTo` | AS2 | `String?` | |
| `tag` | AS2 | `[String]` | |

#### Comment

Subtype of Post with `inReplyTo` required.

#### Reaction

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | Wawa | `String` | ✓ |
| `type` | AS2 | `["Like", "wawa:Reaction"]` | ✓ |
| `object` | AS2 | `String` (ref to target) | ✓ |
| `reactionType` | Wawa | `String` ("👍", "❤️", etc.) | |

#### Follow

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | AS2 | `String` | ✓ |
| `type` | AS2 | `["Follow"]` | ✓ |
| `object` | AS2 | `String` (DID of followed) | ✓ |

#### Block

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | AS2 | `String` | ✓ |
| `type` | AS2 | `["Block"]` | ✓ |
| `object` | AS2 | `String` (DID of blocked) | ✓ |

#### Collection / Album

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | AS2 | `String` | ✓ |
| `type` | AS2 | `["OrderedCollection", "wawa:Collection"]` | ✓ |
| `name` | AS2 | `String?` | |
| `totalItems` | AS2 | `Int` | ✓ |
| `orderedItems` | AS2 | `[String]` (ordered object IDs) | ✓ |

---

### Event

#### RideEvent

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | Wawa | `urn:wawa:ride:...` | ✓ |
| `type` | Wawa+Schema | `["Event", "wawa:RideEvent"]` | ✓ |
| `name` | Schema | `String?` | |
| `summary` | Schema | `String?` | |
| `startDate` | Schema | `Date` | ✓ |
| `endDate` | Schema | `Date?` | |
| `location` | Schema | `Place?` | |
| `rideType` | Wawa | `RideType` (solo, groupRide, relay) | ✓ |
| `visibility` | Wawa | `Visibility` (public, groupOnly, private) | ✓ |
| `meshGroupId` | Wawa | `String?` | |
| `offlineCapable` | Wawa | `Bool` | |
| `participants` | Wawa | `[String]` (DID refs) | |
| `status` | Wawa | `RideStatus` (proposed, active, completed, cancelled) | ✓ |

#### RSVP

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | Wawa | `String` | ✓ |
| `type` | Wawa | `["wawa:RSVP"]` | ✓ |
| `object` | AS2 | `String` (RideEvent ref) | ✓ |
| `response` | Wawa | `RSVPResponse` (yes, no, maybe) | ✓ |

#### Invitation

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | AS2 | `String` | ✓ |
| `type` | AS2 | `["Invite"]` | ✓ |
| `object` | AS2 | `String` (RideEvent ref) | ✓ |
| `target` | AS2 | `String` (invitee DID) | ✓ |
| `secret` | Wawa | `String?` (join secret) | |

#### Attendance

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | Wawa | `String` | ✓ |
| `type` | Wawa | `["wawa:Attendance"]` | ✓ |
| `event` | Wawa | `String` (RideEvent ref) | ✓ |
| `attendee` | Wawa | `String` (Profile ref) | ✓ |
| `role` | Wawa | `AttendanceRole` (leader, sweep, member) | |

---

### Geographic

#### Place

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | Wawa | `urn:wawa:place:...` | ✓ |
| `type` | Schema | `["Place", "wawa:Place"]` | ✓ |
| `name` | Schema | `String?` | |
| `geo` | Schema | `GeoCoordinates` | ✓ |
| `placeType` | Wawa | `PlaceType` | ✓ |

**PlaceType enum:** `meetingPoint`, `hazard`, `waypoint`, `parking`, `fuel`, `photo`, `restStop`, `scenic`

#### Route

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | Wawa | `urn:wawa:route:...` | ✓ |
| `type` | Wawa | `["wawa:RideRoute"]` | ✓ |
| `name` | Wawa | `String?` | |
| `waypoints` | Wawa | `[GeoCoordinates]` | ✓ |
| `distanceMeters` | Wawa | `Double?` | |
| `durationSeconds` | Wawa | `Double?` | |
| `source` | Wawa | `String?` ("valhalla", "gpx", "manual", "recorded") | |

#### Waypoint

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | Wawa | `urn:wawa:waypoint:...` | ✓ |
| `type` | Wawa | `["wawa:Waypoint"]` | ✓ |
| `geo` | Schema | `GeoCoordinates` | ✓ |
| `name` | Schema | `String?` | |
| `order` | Wawa | `Int` (sequence in route) | |
| `waypointType` | Wawa | `WaypointType` | |

**WaypointType enum:** `start`, `via`, `destination`, `rest`, `fuel`, `hazard`, `photo`

#### Track

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | Wawa | `urn:wawa:track:...` | ✓ |
| `type` | Wawa | `["wawa:Track"]` | ✓ |
| `points` | Wawa | `[TrackPoint]` | ✓ |
| `recordedBy` | Wawa | `String` (DID ref) | ✓ |

**TrackPoint:** `{ lat: Double, lon: Double, elevation?: Double, timestamp: Date, speed?: Double, heading?: Double }`

#### HazardBeacon

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | Wawa | `urn:wawa:hazard:...` | ✓ |
| `type` | Wawa | `["wawa:HazardBeacon"]` | ✓ |
| `location` | Schema | `Place` | ✓ |
| `hazardType` | Wawa | `HazardType` | ✓ |
| `description` | Wawa | `String?` | |
| `expiresAt` | Wawa | `Date` | ✓ |
| `confirmations` | Wawa | `[Confirmation]` | |
| `severity` | Wawa | `Severity` (info, caution, danger) | |

**HazardType enum:** `pothole`, `debris`, `animal`, `accident`, `police`, `roadClosure`, `weather`, `other`

#### Confirmation

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | Wawa | `String` | ✓ |
| `type` | Wawa | `["wawa:Confirmation"]` | ✓ |
| `object` | Wawa | `String` (HazardBeacon ref) | ✓ |
| `confirmedBy` | Wawa | `String` (DID ref) | ✓ |
| `timestamp` | Wawa | `Date` | ✓ |
| `stillPresent` | Wawa | `Bool` | ✓ |

---

### Trust & Credentials

#### ClubMembershipCredential

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | VC | `String` | ✓ |
| `type` | VC+Wawa | `["VerifiableCredential", "ClubMembershipCredential"]` | ✓ |
| `issuer` | VC | `String` (club DID) | ✓ |
| `validFrom` | VC | `Date` | ✓ |
| `validUntil` | VC | `Date?` | |
| `credentialSubject.id` | VC | `String` (member DID) | ✓ |
| `credentialSubject.memberOf` | Wawa | `String` (club DID) | ✓ |
| `credentialSubject.role` | Wawa | `MembershipRole` | ✓ |

**MembershipRole enum:** `member`, `admin`, `president`, `roadCaptain`

#### RoleCredential

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | VC | `String` | ✓ |
| `type` | VC+Wawa | `["VerifiableCredential", "RoleCredential"]` | ✓ |
| `issuer` | VC | `String` (club/admin DID) | ✓ |
| `credentialSubject.id` | VC | `String` (member DID) | ✓ |
| `credentialSubject.role` | Wawa | `String` | ✓ |
| `credentialSubject.context` | Wawa | `String?` (scope: club, ride, region) | |

#### Endorsement

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | Wawa | `String` | ✓ |
| `type` | Wawa | `["wawa:Endorsement"]` | ✓ |
| `object` | Wawa | `String` (what is endorsed) | ✓ |
| `endorsee` | Wawa | `String` (who is endorsed) | ✓ |
| `skill` | Wawa | `String` ("roadCaptain", "mechanic", "firstAid") | ✓ |

#### ModerationAction

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | Wawa | `String` | ✓ |
| `type` | Wawa | `["wawa:ModerationAction"]` | ✓ |
| `action` | Wawa | `ModAction` (warn, mute, remove, ban) | ✓ |
| `object` | Wawa | `String` (offending object DID) | ✓ |
| `target` | Wawa | `String` (offender DID) | ✓ |
| `reason` | Wawa | `String` | ✓ |

#### Revocation

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | VC | `String` | ✓ |
| `type` | VC | `["VerifiableCredential", "wawa:Revocation"]` | ✓ |
| `revokes` | Wawa | `String` (credential ID being revoked) | ✓ |
| `reason` | Wawa | `String?` | |

---

### Repository

#### Record

A generic wrapper for repository storage:

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | Wawa | `String` (CID or DID path) | ✓ |
| `type` | Wawa | `["wawa:Record"]` | ✓ |
| `content` | Wawa | `WawaObject` (any ontology object) | ✓ |
| `createdAt` | Wawa | `Date` | ✓ |
| `commitCID` | Wawa | `String?` | |

#### Commit

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `cid` | ATProto | `String` | ✓ |
| `prev` | ATProto | `String?` (previous commit CID) | |
| `data` | ATProto | `[String]` (record CIDs in this commit) | ✓ |
| `sig` | ATProto | `String?` | |
| `createdAt` | ATProto | `Date` | ✓ |

#### ExportManifest

| Field | Source | Type | Required |
|-------|--------|------|----------|
| `id` | Wawa | `String` | ✓ |
| `type` | Wawa | `["wawa:ExportManifest"]` | ✓ |
| `exportedBy` | Wawa | `String` (DID) | ✓ |
| `exportedAt` | Wawa | `Date` | ✓ |
| `records` | Wawa | `[String]` (record IDs included) | ✓ |
| `checksum` | Wawa | `String?` (SHA256 of full export) | |
| `formatVersion` | Wawa | `String` ("1.0") | ✓ |

---

## Protocol Translation: How Each Object Maps

### ActivityPub Translation

A `wawa:RideEvent` → AS2 Activity:

```json
{
  "@context": "https://www.w3.org/ns/activitystreams",
  "type": "Create",
  "actor": "https://wawa.social/users/wagner",
  "object": {
    "type": "Event",
    "name": "Sunday Ride",
    "startDate": "2026-06-15T09:00:00Z",
    "location": { "type": "Place", ... }
  }
}
```

Translation rules:
- `RideEvent` → `Create` activity wrapping an `Event` object
- `RideEvent.status == .proposed` → `Create`
- `RideEvent.status == .cancelled` → `Delete` (tombstone)
- `Profile` → `Person` actor object
- `Post` → `Note`
- `Reaction` → `Like`
- `Follow` → `Follow`
- `Collection` → `OrderedCollection`
- `HazardBeacon` → `Create` with `wawa:HazardBeacon` object

### Nostr Translation

A `wawa:RideEvent` → Nostr event:

```json
{
  "kind": 30000,
  "tags": [
    ["d", "ride-abc"],
    ["wawa-type", "RideEvent"],
    ["location", "48.4284,-123.3656"],
    ["p", "pubkey-of-participant-1"],
    ["p", "pubkey-of-participant-2"]
  ],
  "content": "{...full Wawa JSON-LD...}"
}
```

Translation rules:
- `kind` based on object type (30000 = custom app data, 1 = text note, etc.)
- `content` = full JSON-LD string
- `tags` carry indexed fields for relay filtering (location geohash, participants, wawa-type)
- `Profile` maps to `kind:0` metadata event
- `Post` maps to `kind:1` text note
- `Reaction` maps to `kind:7`
- `HazardBeacon` maps to `kind:30001` with geohash tag
- NIP-44 encrypted DMs for private communication

### ATProto Translation

A `wawa:RideEvent` → ATProto record:

```json
{
  "$type": "social.wawa.ride.event",
  "name": "Sunday Ride",
  "createdAt": "2026-06-15T09:00:00-07:00",
  "route": { "$link": "bafy..." }
}
```

Records sit in collections under the user's DID repository:
- `social.wawa.ride.event`
- `social.wawa.profile`
- `social.wawa.hazard`
- `social.wawa.collection`

### Solid Translation

Objects become JSON-LD resources in a Solid pod:
```
/profile/card
/rides/2026-06-15-sunday-ride.jsonld
/albums/ride-abc/album.jsonld
/hazards/hazard-xyz.jsonld
```

---

## The Three Forms

Every object can exist in three representations:

### 1. Portable (storage/export)

```json
{
  "@context": ["https://www.w3.org/ns/activitystreams", "https://schema.org", "https://wawa.social/ns/v1"],
  "type": ["Event", "wawa:RideEvent"],
  "id": "urn:wawa:ride:01HX...",
  "name": "Sunday Ride",
  ...
}
```

### 2. Signable (verification)

Same JSON, canonicalized via JCS (RFC 8785), then signed:

```json
{
  "...": "...",
  "proof": {
    "type": "Ed25519Signature2020",
    "created": "2026-06-15T09:00:00Z",
    "verificationMethod": "did:key:z6Mk...#key-1",
    "proofPurpose": "assertionMethod",
    "proofValue": "z5kK..."
  }
}
```

### 3. Transport (protocol-specific)

| Channel | Format | Notes |
|---------|--------|-------|
| BLE mesh | Binary (12-469 bytes) | CompactLocation + MeshPacket projection |
| MultipeerKit | JSON (Codable) | LocationPayload, SyncEnvelope |
| Nostr | Event (kind + tags + content) | Full JSON-LD in content |
| ActivityPub | Activity (Create/Update/Delete) | Server-to-server HTTP |
| ATProto | Record in collection | Repository + signed commit |
| QR Code | JSON compressed + base64url | Or link + content hash |
| File export | JSON-LD | `.jsonld` or `.json` |
| Solid | JSON-LD resource | Pod storage |

---

## Identity System

### DID Methods

| Phase | Method | Format | Use Case |
|-------|--------|--------|----------|
| A (current) | `urn:wawa:peer:<hex>` | 8-byte mesh PeerID | Local device identification |
| B | `did:key:z6Mk...` | Ed25519 public key (multibase) | Riders, devices |
| C | `did:web:wawa.social` | Domain-based | Clubs, public entities |

### Credential Flow

```
Issuer (Club)                    Holder (Rider)                   Verifier (App)
     │                                │                                │
     │── ClubMembershipCredential ──→│                                │
     │   (signed JSON-LD)            │                                │
     │                                │── VerifiablePresentation ──→│
     │                                │   (subset: "I'm a member")   │
     │                                │                                │── Verify proof
     │                                │                                │── Check revocation
```

---

## Namespace Registry

All `wawa:*` extensions live under `https://wawa.social/ns/v1`.

### Object Types

| Term | Description |
|------|-------------|
| `wawa:Profile` | Rider/device profile |
| `wawa:Club` | Motorcycle club / organization |
| `wawa:Device` | Mesh device endpoint |
| `wawa:RideEvent` | Motorcycle ride event |
| `wawa:RSVP` | Ride RSVP |
| `wawa:Attendance` | Ride attendance record |
| `wawa:Place` | Geographic place with type |
| `wawa:RideRoute` | Route with waypoints |
| `wawa:Waypoint` | Individual route point |
| `wawa:Track` | Recorded GPS track |
| `wawa:HazardBeacon` | Road hazard alert |
| `wawa:Confirmation` | Hazard confirmation vote |
| `wawa:Collection` | Ordered collection (album, etc.) |
| `wawa:Post` | Social post |
| `wawa:Reaction` | Social reaction |
| `wawa:Endorsement` | Skill/trust endorsement |
| `wawa:Revocation` | Credential revocation |
| `wawa:Record` | Repository record wrapper |
| `wawa:ExportManifest` | Data export manifest |

### Properties

| Term | Type | Description |
|------|------|-------------|
| `peerID` | `string` | Hex-encoded 8-byte mesh identifier |
| `publicKey` | `string` | Multibase-encoded Ed25519 public key |
| `clubs` | `[string]` | Club DID references |
| `rideType` | `RideType` | solo, groupRide, relay |
| `visibility` | `Visibility` | public, groupOnly, private |
| `meshGroupId` | `string` | BLE mesh group identifier |
| `offlineCapable` | `boolean` | Works without internet |
| `participants` | `[string]` | DID references to participants |
| `status` | `RideStatus` | proposed, active, completed, cancelled |
| `placeType` | `PlaceType` | meetingPoint, hazard, waypoint, parking, fuel, photo, restStop, scenic |
| `hazardType` | `HazardType` | pothole, debris, animal, accident, police, roadClosure, weather, other |
| `severity` | `Severity` | info, caution, danger |
| `reactionType` | `string` | Emoji or reaction identifier |
| `confirmedBy` | `string` | DID of confirming rider |
| `stillPresent` | `boolean` | Hazard still observed |
| `recordedBy` | `string` | DID of track recorder |
| `source` | `string` | Route origin ("valhalla", "gpx", "manual", "recorded") |

---

## Implementation Phases

### Phase A (current branch) — Core Ontology
- `WawaObject` protocol
- `WawaContext`, `WawaValue`, `WawaIdentifier`, `WawaProof`
- `WawaEncoder` / `WawaDecoder`
- `JCS` stub
- Types: `Profile`, `RideEvent`, `Place`, `Route`, `MediaObject`, `WawaCollection`
- Integration: `WawaPersistence` JSON-LD columns, `RideSession` profile usage

### Phase B — Identity
- Ed25519 key generation (CryptoKit)
- `did:key` creation and parsing
- Full `JCS` canonicalization (RFC 8785)
- Sign/verify on `WawaProof`
- `Device` type

### Phase C — Credentials + Transport
- `ClubMembershipCredential`, `RoleCredential`
- `Endorsement`, `Confirmation`, `Revocation`
- Nostr event mapper
- `VerifiablePresentation` subset

### Phase D — Full Interop
- ActivityPub mapper
- ATProto record mapper
- Solid pod integration
- Export/import with `ExportManifest`
- `wawa.social/ns/v1` namespace registration
- `HazardBeacon`, `Track`, `Waypoint`, `Attendance` types
