import Foundation
import Automerge

/// Automerge-based CRDT document for rider state synchronization.
///
/// When riders go offline and reconnect, their position histories diverge.
/// Automerge's sync protocol reconciles these divergences in 2-4 messages
/// without conflicts, using a bloom-filter-based delta exchange.
///
/// Why Automerge over OrbitDB or custom sync?
/// - Automerge: 6.3k stars, MIT, native Swift bindings (automerge-swift, 317 stars)
/// - OrbitDB: 8.8k stars but JS-only, no iOS support, requires IPFS stack
/// - Custom: reinventing CRDTs is error-prone; Automerge is formally verified
///
/// Reference: https://github.com/automerge/automerge-swift
/// Sync protocol paper: https://arxiv.org/abs/2012.00472
///
/// How sync works (from the paper):
/// 1. Peer A sends its "heads" (latest change hashes) + bloom filter of known changes
/// 2. Peer B identifies which changes A is missing (not in bloom) and sends them
/// 3. A applies changes; the CRDT merge function ensures deterministic convergence
/// 4. After 2-4 round trips, both peers have identical state
///
/// Data model for Wawa Ride:
/// ```
/// Document {
///   riders: Map<PeerID, { lat, lon, hdg, spd, ts }>  // last known position per rider
/// }
/// ```
///
/// See also:
/// - Berty's OrbitDB usage for append-only message logs: https://github.com/berty/berty
/// - automerge-repo-swift for pluggable network adapters: https://github.com/automerge/automerge-repo-swift
public final class RideSyncDocument: @unchecked Sendable {
    private var doc: Document
    private let actorId: ActorId

    public init(actorId: Data) {
        self.actorId = ActorId(actorId)
        self.doc = Document(actor: self.actorId)
    }

    /// Update local rider position in the CRDT document.
    /// Each call creates a new "change" in Automerge's DAG.
    public func updateRider(id: String, lat: Double, lon: Double, heading: Double?, speed: Double?) {
        let riders = doc.root.get(key: "riders") ?? doc.root.put(key: "riders", obj: .Map)
        guard case let .Object(ridersObj) = riders else { return }
        let rider = ridersObj.get(key: id) ?? ridersObj.put(key: id, obj: .Map)
        guard case let .Object(riderObj) = rider else { return }
        riderObj.put(key: "lat", value: .F64(lat))
        riderObj.put(key: "lon", value: .F64(lon))
        riderObj.put(key: "ts", value: .F64(Date().timeIntervalSince1970))
        if let h = heading { riderObj.put(key: "hdg", value: .F64(h)) }
        if let s = speed { riderObj.put(key: "spd", value: .F64(s)) }
    }

    /// Generate a sync message to send to a peer.
    /// Uses Automerge's bloom-filter protocol for efficient delta exchange.
    /// Reference: SyncState tracks what each peer has seen (heads + bloom filter).
    public func generateSyncMessage(for peerState: inout SyncState) -> Data? {
        doc.generateSyncMessage(state: &peerState)
    }

    /// Receive and apply a sync message from a peer.
    /// Automerge merges changes deterministically (CRDT guarantee: no conflicts).
    public func receiveSyncMessage(_ message: Data, from peerState: inout SyncState) throws {
        try doc.receiveSyncMessage(state: &peerState, message: message)
    }

    /// Read all rider positions from the document.
    public func allRiders() -> [String: RiderState] {
        guard case let .Object(ridersObj) = doc.root.get(key: "riders") else { return [:] }
        var result: [String: RiderState] = [:]
        for key in ridersObj.keys() {
            guard case let .Object(riderObj) = ridersObj.get(key: key),
                  case let .Scalar(.F64(lat)) = riderObj.get(key: "lat"),
                  case let .Scalar(.F64(lon)) = riderObj.get(key: "lon") else { continue }
            let hdg: Double? = if case let .Scalar(.F64(v)) = riderObj.get(key: "hdg") { v } else { nil }
            let spd: Double? = if case let .Scalar(.F64(v)) = riderObj.get(key: "spd") { v } else { nil }
            let ts: Double = if case let .Scalar(.F64(v)) = riderObj.get(key: "ts") { v } else { 0 }
            result[key] = RiderState(lat: lat, lon: lon, heading: hdg, speed: spd, timestamp: ts)
        }
        return result
    }

    /// Export document bytes for persistence (store in GRDB or file).
    public func save() -> Data { doc.save() }

    /// Load from previously saved bytes.
    public func load(_ data: Data) throws { doc = try Document(data) }
}

public struct RiderState: Sendable {
    public let lat: Double
    public let lon: Double
    public let heading: Double?
    public let speed: Double?
    public let timestamp: Double
}
