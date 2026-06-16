import XCTest
@testable import WawaMesh
import BitFoundation

/// Tests for BitChat BinaryProtocol integration with WawaMesh payloads.
final class BinaryCodecTests: XCTestCase {

    // MARK: - BinaryProtocol round-trip (via BitchatPacket public API)

    func testRoundTrip() throws {
        let original = BitchatPacket(
            type: 0x02,  // locationUpdate
            ttl: 5,
            senderID: Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]),
            payload: "hello".data(using: .utf8)!
        )
        let encoded = try XCTUnwrap(original.toBinaryData())
        let decoded = try XCTUnwrap(BitchatPacket.from(encoded))
        XCTAssertEqual(decoded.type, 0x02)
        XCTAssertEqual(decoded.ttl, 5)
        XCTAssertEqual(decoded.senderID, original.senderID)
        XCTAssertEqual(decoded.payload, original.payload)
        XCTAssertNil(decoded.recipientID)
        XCTAssertNil(decoded.signature)
    }

    func testUnicast() throws {
        let recipient = Data([0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8])
        let original = BitchatPacket(
            type: 0x03,  // routeShare
            senderID: Data(repeating: 0x01, count: 8),
            recipientID: recipient,
            payload: Data([0xFF])
        )
        let encoded = try XCTUnwrap(original.toBinaryData())
        let decoded = try XCTUnwrap(BitchatPacket.from(encoded))
        XCTAssertEqual(decoded.recipientID, recipient)
    }

    // MARK: - Dedup

    func testDeduplicator() {
        let dedup = MessageDeduplicator()
        XCTAssertTrue(dedup.isNew("msg-1"))
        XCTAssertFalse(dedup.isNew("msg-1"))
        XCTAssertTrue(dedup.isNew("msg-2"))
    }

    // MARK: - Fragmentation

    func testFragmentation() throws {
        let bigPayload = Data(repeating: 0xAB, count: 2000)
        let packet = BitchatPacket(
            type: 0x02,
            senderID: Data(repeating: 0x01, count: 8),
            payload: bigPayload
        )
        let encoded = try XCTUnwrap(packet.toBinaryData())
        let fragments = FragmentCodec.fragment(encoded, maxSize: 469)
        XCTAssertGreaterThan(fragments.count, 1)
        XCTAssertTrue(FragmentCodec.isFragment(fragments[0]))

        let assembly = FragmentAssemblyBuffer()
        let peer = UUID()
        var result: Data?
        for frag in fragments {
            result = assembly.addFragment(frag, from: peer)
        }
        let reassembled = try XCTUnwrap(result)
        let decoded = try XCTUnwrap(BitchatPacket.from(reassembled))
        XCTAssertEqual(decoded.payload, bigPayload)
    }

    // MARK: - CompactLocation

    func testCompactLocationRoundTrip() throws {
        let original = CompactLocation(latitude: -23.5505199, longitude: -46.6333094, heading: 275, speed: 13.9)
        let encoded = original.encode()
        XCTAssertEqual(encoded.count, 12)

        let decoded = try XCTUnwrap(CompactLocation.decode(encoded))
        XCTAssertEqual(decoded.latitude, -23.5505199, accuracy: 0.0000002)
        XCTAssertEqual(decoded.longitude, -46.6333094, accuracy: 0.0000002)
        XCTAssertEqual(decoded.headingDegrees, 275)
        XCTAssertEqual(decoded.speedMps, 13.9, accuracy: 0.1)
    }

    func testCompactLocationSize() {
        let loc = CompactLocation(latitude: -23.5505, longitude: -46.6333, heading: 180, speed: 27.8)
        let jsonSize = try! JSONEncoder().encode(LocationPayload(
            lat: -23.5505, lon: -46.6333, heading: 180, speed: 27.8, accuracy: 10, timestamp: 0
        )).count
        XCTAssertEqual(loc.encode().count, 12)
        XCTAssertGreaterThan(jsonSize, 60)
    }

    // MARK: - Wawa-specific types work as BitchatPacket payloads

    func testAnnounceViaBitChat() throws {
        let announce = AnnouncePayload(nickname: "TestRider", groupID: "group-abc", visibility: .public)
        let json = try JSONEncoder().encode(announce)
        let packet = BitchatPacket(
            type: MessageType.announce.rawValue,
            senderID: Data(repeating: 0x42, count: 8),
            payload: json
        )
        let encoded = try XCTUnwrap(packet.toBinaryData())
        let decoded = try XCTUnwrap(BitchatPacket.from(encoded))
        let decodedAnnounce = try JSONDecoder().decode(AnnouncePayload.self, from: decoded.payload)
        XCTAssertEqual(decodedAnnounce.nickname, "TestRider")
        XCTAssertEqual(decodedAnnounce.groupID, "group-abc")
    }

    func testLocationViaBitChat() throws {
        let loc = CompactLocation(latitude: -23.5505, longitude: -46.6333, heading: 180, speed: 27.8)
        let packet = BitchatPacket(
            type: 0x02,  // locationUpdate
            senderID: Data(repeating: 0x01, count: 8),
            payload: loc.encode()
        )
        let encoded = try XCTUnwrap(packet.toBinaryData())
        let decoded = try XCTUnwrap(BitchatPacket.from(encoded))
        XCTAssertEqual(decoded.type, 0x02)
        let decodedLoc = try XCTUnwrap(CompactLocation.decode(decoded.payload))
        XCTAssertEqual(decodedLoc.latitude, -23.5505, accuracy: 0.0001)
        XCTAssertEqual(decodedLoc.longitude, -46.6333, accuracy: 0.0001)
    }
}
