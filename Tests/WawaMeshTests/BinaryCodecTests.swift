import XCTest
@testable import WawaMesh

final class BinaryCodecTests: XCTestCase {
    func testRoundTrip() throws {
        let original = MeshPacket(
            type: .locationUpdate, ttl: 5,
            senderID: Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]),
            payload: "hello".data(using: .utf8)!
        )
        let encoded = BinaryCodec.encode(original)
        let decoded = try XCTUnwrap(BinaryCodec.decode(encoded))
        XCTAssertEqual(decoded.type, .locationUpdate)
        XCTAssertEqual(decoded.ttl, 5)
        XCTAssertEqual(decoded.senderID, original.senderID)
        XCTAssertEqual(decoded.payload, original.payload)
        XCTAssertNil(decoded.recipientID)
        XCTAssertNil(decoded.signature)
    }

    func testUnicast() throws {
        let recipient = Data([0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8])
        let original = MeshPacket(
            type: .routeShare,
            senderID: Data(repeating: 0x01, count: 8),
            recipientID: recipient,
            payload: Data([0xFF])
        )
        let decoded = try XCTUnwrap(BinaryCodec.decode(BinaryCodec.encode(original)))
        XCTAssertEqual(decoded.recipientID, recipient)
    }

    func testDeduplicator() {
        let dedup = MessageDeduplicator()
        XCTAssertTrue(dedup.isNew("msg-1"))
        XCTAssertFalse(dedup.isNew("msg-1"))
        XCTAssertTrue(dedup.isNew("msg-2"))
    }

    func testFragmentation() throws {
        let bigPayload = Data(repeating: 0xAB, count: 2000)
        let packet = MeshPacket(type: .locationUpdate, senderID: Data(repeating: 0x01, count: 8), payload: bigPayload)
        let encoded = BinaryCodec.encode(packet)
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
        let decoded = try XCTUnwrap(BinaryCodec.decode(reassembled))
        XCTAssertEqual(decoded.payload, bigPayload)
    }
}


    func testCompactLocationRoundTrip() throws {
        let original = CompactLocation(latitude: -23.5505199, longitude: -46.6333094, heading: 275, speed: 13.9)
        let encoded = original.encode()
        XCTAssertEqual(encoded.count, 12)  // Always 12 bytes

        let decoded = try XCTUnwrap(CompactLocation.decode(encoded))
        XCTAssertEqual(decoded.latitude, -23.5505199, accuracy: 0.0000002)  // ~2cm precision
        XCTAssertEqual(decoded.longitude, -46.6333094, accuracy: 0.0000002)
        XCTAssertEqual(decoded.headingDegrees, 275)
        XCTAssertEqual(decoded.speedMps, 13.9, accuracy: 0.1)
    }

    func testCompactLocationSize() {
        // JSON equivalent would be ~80 bytes. Protobuf-style is 12 bytes = 85% reduction
        let loc = CompactLocation(latitude: -23.5505, longitude: -46.6333, heading: 180, speed: 27.8)
        let jsonSize = try! JSONEncoder().encode(LocationPayload(
            lat: -23.5505, lon: -46.6333, heading: 180, speed: 27.8, accuracy: 10, timestamp: 0
        )).count
        XCTAssertEqual(loc.encode().count, 12)
        XCTAssertGreaterThan(jsonSize, 60)  // JSON is 5-7x larger
    }
