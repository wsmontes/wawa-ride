// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WawaRide",
    platforms: [.iOS(.v16)],
    products: [
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
    ],
    targets: [
        .target(name: "WawaMesh", dependencies: [
            .product(name: "MultipeerKit", package: "MultipeerKit"),
        ], path: "Sources/WawaMesh"),
        .testTarget(name: "WawaMeshTests", dependencies: ["WawaMesh"], path: "Tests/WawaMeshTests"),

        .target(name: "WawaMap", dependencies: [
            .product(name: "MapLibreSwiftUI", package: "swiftui-dsl"),
        ], path: "Sources/WawaMap"),

        .target(name: "WawaNavigation", dependencies: [
            .product(name: "FerrostarCore", package: "ferrostar"),
            .product(name: "FerrostarSwiftUI", package: "ferrostar"),
            .product(name: "FerrostarMapLibreUI", package: "ferrostar"),
        ], path: "Sources/WawaNavigation"),

        .target(name: "WawaPersistence", dependencies: [
            .product(name: "GRDB", package: "GRDB.swift"),
            .product(name: "Automerge", package: "automerge-swift"),
        ], path: "Sources/WawaPersistence"),

        .executableTarget(
            name: "WawaRideApp",
            dependencies: ["WawaMesh", "WawaMap", "WawaNavigation", "WawaPersistence"],
            path: "Sources/WawaRideApp",
            resources: [.process("Resources")]
        ),
    ]
)
