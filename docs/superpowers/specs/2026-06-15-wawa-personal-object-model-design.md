# Wawa Personal Object Model — Design Spec

**Date:** 2026-06-15
**Status:** Approved — Scope A implementation in progress
**Branch:** `v2/mesh-maplibre-ferrostar`

## Summary

Define a portable JSON ontology for personal, social, and verifiable objects used by WawaRide. The ontology is a **profile of interoperability** — it uses existing standards (ActivityStreams, Schema.org, DID, VC) with minimal `wawa:*` extensions, and is translatable to ActivityPub, Nostr, ATProto, and Solid.

The golden rule:

> WawaRide does not "use a social protocol."
> It produces objects compatible with the maximum number of existing social protocols.

## Field Preference Order

```
1. If it exists in ActivityStreams, use ActivityStreams.
2. If it exists in Schema.org, use Schema.org.
3. If it's a verifiable claim, use Verifiable Credentials.
4. If it's identity, use DID.
5. If it's transport/publication, map to Nostr/ActivityPub/ATProto.
6. Only create wawa:* if no good equivalent exists.
```

## Three Forms, One Object

| Form | Purpose | Format |
|------|---------|--------|
| Portable | Human-readable, exportable | JSON-LD |
| Signable | Cryptographic verification | JCS canonical + proof envelope |
| Transport | Wire efficiency | Protocol-specific (BLE binary, Nostr event, AP activity) |

## Core Concepts & Protocol Mapping

| Concept | Wawa Field | ActivityStreams | Schema.org | DID/VC | Nostr | ATProto |
|---------|-----------|-----------------|------------|--------|-------|---------|
| Identifier | `id` | `id` | `@id` | `id` | `id` | URI/CID |
| Type | `type` + `wawaType` | `type` | `@type` | `type` | `kind` | `$type` |
| Author | `attributedTo` | `actor`/`attributedTo` | `author`/`creator` | `issuer` | `pubkey` | repo DID |
| Timestamp | `published`/`updated` | `published` | `datePublished` | `validFrom` | `created_at` | record key |
| Target | `object`/`target` | `object`/`target` | specific rels | `credentialSubject` | `tags` | record refs |
| Content | semantic fields | `content`/`name` | `name`/`description` | claims | `content` | record fields |
| Proof | `proof` | external | external | `proof`/JOSE | `sig` | signed commit |
| Media | `attachment`/`media` | `Link`/`Image` | `ImageObject` | related resource | tags/content | blob CID |
| Extension | `@context` | JSON-LD context | vocab | credential schema | NIPs | Lexicon |

## Module Structure

```
Sources/WawaOntology/
  WawaOntology.swift              -- re-exports, module docs
  Core/
    WawaObject.swift              -- base protocol
    WawaContext.swift             -- @context registry
    WawaIdentifier.swift          -- URN/DID/id factory
    WawaProof.swift               -- proof envelope
  Types/
    Profile.swift                 -- Person + profile
    RideEvent.swift               -- Event + ride
    Place.swift                   -- Place + GeoCoordinates
    Route.swift                   -- Route + waypoints
    MediaObject.swift             -- ImageObject / attachment
    Collection.swift              -- OrderedCollection
  Codec/
    WawaEncoder.swift             -- JSON-LD serialization
    WawaDecoder.swift             -- JSON-LD deserialization
    JCS.swift                     -- RFC 8785 canonicalization stub
```

Zero external dependencies. Foundation only.

## Core Protocol: WawaObject

```swift
public protocol WawaObject: Codable, Sendable, Identifiable where ID == String {
    static var contexts: [WawaContext] { get }
    static var wawaType: String { get }
    static var additionalTypes: [String] { get }
    var id: String { get }
    var attributedTo: String? { get }
    var published: Date { get }
    var updated: Date? { get }
    var proof: WawaProof? { get set }
    var wawaExtensions: [String: WawaValue] { get set }
}
```

## Concrete Types

| Type | wawaType | additionalTypes | Maps From |
|------|----------|-----------------|-----------|
| `Profile` | `wawa:Profile` | `Person` | PeerID, future Ed25519 key |
| `RideEvent` | `wawa:RideEvent` | `Event` | `Ride` (GRDB), `RideSession` |
| `Place` | `wawa:Place` | `Place` | `Waypoint` (GRDB), `CompactLocation` |
| `Route` | `wawa:RideRoute` | — | `RouteCorridor`, `MatchedRoute` |
| `MediaObject` | — | `ImageObject` | new |
| `WawaCollection` | `wawa:Collection` | `OrderedCollection` | new |

## JSON-LD Shape Examples

### Profile

```json
{
  "@context": ["https://www.w3.org/ns/activitystreams", "https://schema.org", "https://wawa.social/ns/v1"],
  "type": ["Person", "wawa:Profile"],
  "id": "urn:wawa:peer:a1b2c3d4e5f6g7h8",
  "name": "Wagner",
  "peerID": "a1b2c3d4e5f6g7h8"
}
```

### RideEvent

```json
{
  "@context": ["https://www.w3.org/ns/activitystreams", "https://schema.org", "https://wawa.social/ns/v1"],
  "type": ["Event", "wawa:RideEvent"],
  "id": "urn:wawa:ride:01HX3K9M...",
  "name": "Sunday Ride",
  "attributedTo": "urn:wawa:peer:a1b2c3d4e5f6g7h8",
  "startDate": "2026-06-15T09:00:00Z",
  "location": { "type": "Place", "geo": { "latitude": 48.4284, "longitude": -123.3656 } },
  "rideType": "groupRide",
  "visibility": "groupOnly",
  "status": "active"
}
```

## Architecture Rule: Transport Projection

```
WawaObject (semantic)
    ├─→ WawaEncoder → JSON-LD (storage, export, Nostr/AP future)
    └─→ CompactProjection → BinaryCodec (BLE mesh today)
```

The BLE transports a compact binary payload. The meaning of that payload points to this ontology.

## Implementation Sequence (Scope A)

1. `WawaContext`, `WawaValue`, `WawaIdentifier` — 3 files, no dependencies
2. `WawaObject` protocol + `WawaProof` — 2 files
3. `WawaEncoder` + `WawaDecoder` — 2 files
4. Concrete types: `Profile`, `RideEvent`, `Place`, `Route`, `MediaObject`, `WawaCollection` — 6 files
5. `JCS` canonicalization stub — 1 file
6. `Package.swift` — new `WawaOntology` target
7. Wire into `WawaPersistence` — JSON-LD column on `ride` and `waypoint` tables
8. Wire into `WawaRideApp/RideSession` — use `Profile` for peer identity
9. Tests: round-trip encode/decode for each type

## Scoped Out (Future Phases)

| Item | Phase |
|------|-------|
| Ed25519 key generation, `did:key` | B — Core + Identity |
| VerifiableCredential implementation | C — Credentials |
| Nostr event mapper | C/D |
| ActivityPub mapper | D |
| ATProto record mapper | D |
| Solid pod integration | D |
| Full JCS RFC 8785 compliance | B |
| Export manifest, repo versioning | C |

## Protocol References

- JSON-LD 1.1 — https://www.w3.org/TR/json-ld11/
- Activity Streams 2.0 — https://www.w3.org/TR/activitystreams-core/
- ActivityPub — https://www.w3.org/TR/activitypub/
- Schema.org — https://schema.org/docs/schemas.html
- DID 1.0 — https://www.w3.org/TR/did-1.0/
- Verifiable Credentials 2.0 — https://www.w3.org/TR/vc-data-model-2.0/
- JCS (RFC 8785) — https://www.rfc-editor.org/rfc/rfc8785
- AT Protocol Data Model — https://atproto.com/specs/data-model
- AT Protocol Repository — https://atproto.com/specs/repository
- Nostr NIP-01 — https://github.com/nostr-protocol/nips/blob/master/01.md
- Solid Protocol — https://solidproject.org/TR/protocol
