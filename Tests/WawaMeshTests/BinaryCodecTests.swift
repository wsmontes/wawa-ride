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
