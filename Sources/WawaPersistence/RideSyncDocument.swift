import Foundation
import Automerge

/// Automerge-based CRDT document for rider state.
/// When peers reconnect after offline gap, sync protocol reconciles in 2-4 messages.
public final class RideSyncDocument: @unchecked Sendable {
    private var doc: Document
    private let actorId: ActorId

    public init(actorId: Data) {
        self.actorId = ActorId(actorId)
        self.doc = Document(actor: self.actorId)
    }

    /// Update local rider position in the CRDT doc.
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

    /// Generate sync message to send to a peer.
    public func generateSyncMessage(for peerState: inout SyncState) -> Data? {
        doc.generateSyncMessage(state: &peerState)
    }

    /// Receive and apply a sync message from a peer.
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

    /// Export document bytes for persistence.
    public func save() -> Data { doc.save() }

    /// Load from saved bytes.
    public func load(_ data: Data) throws { doc = try Document(data) }
}

public struct RiderState: Sendable {
    public let lat: Double
    public let lon: Double
    public let heading: Double?
    public let speed: Double?
    public let timestamp: Double
}
