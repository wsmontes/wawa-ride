// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WawaRide",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "BitLogger", targets: ["BitLogger"]),
        .library(name: "BitFoundation", targets: ["BitFoundation"]),
        .library(name: "WawaOntology", targets: ["WawaOntology"]),
        .library(name: "WawaMesh", targets: ["WawaMesh"]),
        .library(name: "WawaMap", targets: ["WawaMap"]),
        .library(name: "WawaNavigation", targets: ["WawaNavigation"]),
        .library(name: "WawaPersistence", targets: ["WawaPersistence"]),
    ],
    dependencies: [
        // Map rendering (official SwiftUI DSL wrapper)
        .package(url: "https://github.com/maplibre/swiftui-dsl", from: "0.25.0"),
        // Navigation (Ferrostar + Valhalla, phase 2)
        .package(url: "https://github.com/stadiamaps/ferrostar", from: "0.51.0"),
        // Persistence (SQLite with reactive observation)
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.0"),
        // CRDT sync (offline reconciliation when riders reconnect)
        .package(url: "https://github.com/automerge/automerge-swift", from: "0.5.0"),
        // MultipeerConnectivity (foreground Wi-Fi Direct transport)
        .package(url: "https://github.com/insidegui/MultipeerKit", from: "0.4.0"),
        // Compact binary serialization (12-14 bytes per location vs 80 bytes JSON)
        .package(url: "https://github.com/apple/swift-protobuf", from: "1.28.0"),
        // Geospatial computations (route corridor, point-to-line distance)
        .package(url: "https://github.com/mapbox/turf-swift", from: "4.0.0"),
        // BLE mock for Simulator testing (no physical devices needed)
        .package(url: "https://github.com/NordicSemiconductor/IOS-CoreBluetooth-Mock", from: "0.17.0"),
    ],
    targets: [
        .target(name: "BitLogger", dependencies: [], path: "Sources/BitLogger"),
        .target(name: "BitFoundation", dependencies: ["BitLogger"], path: "Sources/BitFoundation"),

        .target(name: "WawaOntology", dependencies: [], path: "Sources/WawaOntology"),
        .testTarget(name: "WawaOntologyTests", dependencies: ["WawaOntology"], path: "Tests/WawaOntologyTests"),

        .target(name: "WawaMesh", dependencies: [
            "BitFoundation",
            "WawaOntology",
            .product(name: "MultipeerKit", package: "MultipeerKit"),
            .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            .product(name: "CoreBluetoothMock", package: "IOS-CoreBluetooth-Mock"),
        ], path: "Sources/WawaMesh"),
        .testTarget(name: "WawaMeshTests", dependencies: ["WawaMesh"], path: "Tests/WawaMeshTests"),

        .target(name: "WawaMap", dependencies: [
            .product(name: "MapLibreSwiftUI", package: "swiftui-dsl"),
            .product(name: "Turf", package: "turf-swift"),
        ], path: "Sources/WawaMap"),

        .target(name: "WawaNavigation", dependencies: [
            .product(name: "FerrostarCore", package: "ferrostar"),
            .product(name: "FerrostarSwiftUI", package: "ferrostar"),
            .product(name: "FerrostarMapLibreUI", package: "ferrostar"),
        ], path: "Sources/WawaNavigation"),

        .target(name: "WawaPersistence", dependencies: [
            "WawaOntology",
            .product(name: "GRDB", package: "GRDB.swift"),
            .product(name: "Automerge", package: "automerge-swift"),
        ], path: "Sources/WawaPersistence"),

        .executableTarget(
            name: "WawaRideApp",
            dependencies: ["WawaOntology", "WawaMesh", "WawaMap", "WawaNavigation", "WawaPersistence"],
            path: "Sources/WawaRideApp",
            resources: [.process("Resources")]
        ),
    ]
)
