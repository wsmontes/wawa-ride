import XCTest
@testable import WawaOntology

/// Round-trip tests for WawaOntology types.
///
/// Every type must survive encode → decode without data loss.
final class WawaEncoderTests: XCTestCase {

    let encoder = WawaEncoder()
    let decoder = WawaDecoder()

    // MARK: - Profile

    func testProfileRoundTrip() throws {
        let profile = Profile(
            id: "urn:wawa:peer:a1b2c3d4e5f6g7h8",
            name: "Wagner",
            givenName: "Wagner",
            familyName: "Montes",
            peerID: "a1b2c3d4e5f6g7h8",
            clubs: ["did:key:clubBrazoocas"]
        )

        let data = try encoder.encode(profile)
        let decoded = try decoder.decode(Profile.self, from: data)

        XCTAssertEqual(decoded.id, profile.id)
        XCTAssertEqual(decoded.name, profile.name)
        XCTAssertEqual(decoded.peerID, profile.peerID)
        XCTAssertEqual(decoded.clubs, profile.clubs)
    }

    func testProfileJSONShape() throws {
        let profile = Profile(
            id: "urn:wawa:peer:a1b2c3d4e5f6g7h8",
            name: "Wagner",
            peerID: "a1b2c3d4e5f6g7h8"
        )

        let data = try encoder.encode(profile)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Must have @context
        XCTAssertNotNil(dict["@context"])

        // Must have type array with Person and wawa:Profile
        let types = dict["type"] as? [String] ?? []
        XCTAssertTrue(types.contains("Person"))
        XCTAssertTrue(types.contains("wawa:Profile"))

        // Must have id, name, peerID
        XCTAssertEqual(dict["id"] as? String, "urn:wawa:peer:a1b2c3d4e5f6g7h8")
        XCTAssertEqual(dict["name"] as? String, "Wagner")
        XCTAssertEqual(dict["peerID"] as? String, "a1b2c3d4e5f6g7h8")
    }

    // MARK: - RideEvent

    func testRideEventRoundTrip() throws {
        let event = RideEvent(
            id: "urn:wawa:ride:01HX3K9M2Qv7",
            attributedTo: "urn:wawa:peer:a1b2c3d4e5f6g7h8",
            name: "Sunday Ride",
            summary: "Victoria to Sooke via Highway 14",
            startDate: ISO8601DateFormatter().date(from: "2026-06-15T09:00:00Z")!,
            location: Place(
                id: "urn:wawa:place:01HX4L0N3Rw8",
                name: "Victoria Tim Hortons",
                geo: GeoCoordinates(latitude: 48.4284, longitude: -123.3656),
                placeType: .meetingPoint
            ),
            rideType: .groupRide,
            visibility: .groupOnly,
            meshGroupId: "ride-abc",
            participants: ["urn:wawa:peer:a1b2c3d4e5f6g7h8"],
            status: .active
        )

        let data = try encoder.encode(event)
        let decoded = try decoder.decode(RideEvent.self, from: data)

        XCTAssertEqual(decoded.id, event.id)
        XCTAssertEqual(decoded.name, event.name)
        XCTAssertEqual(decoded.rideType, event.rideType)
        XCTAssertEqual(decoded.status, event.status)
        XCTAssertEqual(decoded.location?.geo.latitude, 48.4284)
        XCTAssertEqual(decoded.participants, event.participants)
    }

    func testRideEventJSONShape() throws {
        let event = RideEvent(
            id: "urn:wawa:ride:01HX3K9M2Qv7",
            name: "Sunday Ride",
            startDate: Date(),
            rideType: .solo,
            visibility: .private,
            status: .proposed
        )

        let data = try encoder.encode(event)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Type should include Event
        let types = dict["type"] as? [String] ?? []
        XCTAssertTrue(types.contains("Event"))
        XCTAssertTrue(types.contains("wawa:RideEvent"))
    }

    // MARK: - Place

    func testPlaceRoundTrip() throws {
        let place = Place(
            id: "urn:wawa:place:01HX4L0N3Rw8",
            name: "Rotten Ronnie's",
            geo: GeoCoordinates(latitude: 48.4284, longitude: -123.3656, elevation: 10.0),
            placeType: .fuel
        )

        let data = try encoder.encode(place)
        let decoded = try decoder.decode(Place.self, from: data)

        XCTAssertEqual(decoded.id, place.id)
        XCTAssertEqual(decoded.name, place.name)
        XCTAssertEqual(decoded.geo.latitude, 48.4284)
        XCTAssertEqual(decoded.geo.longitude, -123.3656)
        XCTAssertEqual(decoded.geo.elevation, 10.0)
        XCTAssertEqual(decoded.placeType, .fuel)
    }

    // MARK: - Route

    func testRouteRoundTrip() throws {
        let route = Route(
            id: "urn:wawa:route:01HX5M1P4Sx9",
            name: "Victoria to Sooke",
            waypoints: [
                GeoCoordinates(latitude: 48.4284, longitude: -123.3656),
                GeoCoordinates(latitude: 48.3762, longitude: -123.7378)
            ],
            distanceMeters: 42000.0,
            durationSeconds: 2700.0,
            source: "valhalla"
        )

        let data = try encoder.encode(route)
        let decoded = try decoder.decode(Route.self, from: data)

        XCTAssertEqual(decoded.id, route.id)
        XCTAssertEqual(decoded.name, route.name)
        XCTAssertEqual(decoded.waypoints.count, 2)
        XCTAssertEqual(decoded.distanceMeters, 42000.0)
        XCTAssertEqual(decoded.source, "valhalla")
    }

    // MARK: - WawaCollection

    func testCollectionRoundTrip() throws {
        let collection = WawaCollection(
            id: "urn:wawa:collection:01HX6N2Q5Ty0",
            name: "Sunday Ride Photos",
            summary: "Photos from the June 15th ride",
            totalItems: 3,
            orderedItems: [
                "urn:wawa:media:img001",
                "urn:wawa:media:img002",
                "urn:wawa:media:img003"
            ]
        )

        let data = try encoder.encode(collection)
        let decoded = try decoder.decode(WawaCollection.self, from: data)

        XCTAssertEqual(decoded.id, collection.id)
        XCTAssertEqual(decoded.name, collection.name)
        XCTAssertEqual(decoded.totalItems, 3)
        XCTAssertEqual(decoded.orderedItems, collection.orderedItems)
    }

    // MARK: - WawaValue

    func testWawaValueRoundTrip() throws {
        let extensions: [String: WawaValue] = [
            "stringField": .string("hello"),
            "intField": .integer(42),
            "doubleField": .number(3.14),
            "boolField": .boolean(true),
            "arrayField": .array([.string("a"), .string("b")]),
            "objectField": .object(["nested": .string("value")]),
            "nullField": .null
        ]

        let data = try JSONEncoder().encode(extensions)
        let decoded = try JSONDecoder().decode([String: WawaValue].self, from: data)

        XCTAssertEqual(decoded["stringField"]?.stringValue, "hello")
        XCTAssertEqual(decoded["intField"]?.intValue, 42)
        XCTAssertEqual(decoded["doubleField"]?.doubleValue, 3.14)
        XCTAssertEqual(decoded["boolField"]?.boolValue, true)
        XCTAssertEqual(decoded["arrayField"]?.arrayValue?.count, 2)
        XCTAssertEqual(decoded["nullField"], .null)
    }

    // MARK: - Type discrimination

    func testTypeOf() throws {
        let event = RideEvent(
            id: "urn:wawa:ride:test",
            name: "Test",
            startDate: Date(),
            rideType: .solo,
            visibility: .public,
            status: .proposed
        )
        let data = try encoder.encode(event)
        let wawaType = try decoder.typeOf(data)
        XCTAssertEqual(wawaType, "wawa:RideEvent")
    }

    // MARK: - Encode to string

    func testEncodeToString() throws {
        let profile = Profile(id: "urn:wawa:peer:test", name: "Test")
        let string = try encoder.encodeToString(profile)
        XCTAssertTrue(string.contains("@context"))
        XCTAssertTrue(string.contains("wawa:Profile"))
    }
}
