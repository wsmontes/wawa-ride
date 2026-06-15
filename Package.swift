// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WawaRide",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "WawaMesh", targets: ["WawaMesh"]),
        .library(name: "WawaMap", targets: ["WawaMap"]),
        .library(name: "WawaNavigation", targets: ["WawaNavigation"]),
    ],
    dependencies: [
        .package(url: "https://github.com/maplibre/maplibre-gl-native-distribution", from: "6.27.0"),
        .package(url: "https://github.com/stadiamaps/ferrostar", from: "0.51.0"),
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift", from: "0.21.1"),
    ],
    targets: [
        // MARK: - WawaMesh (BLE multi-hop + Nostr fallback)
        .target(
            name: "WawaMesh",
            dependencies: [.product(name: "secp256k1", package: "secp256k1.swift")],
            path: "Sources/WawaMesh"
        ),
        .testTarget(name: "WawaMeshTests", dependencies: ["WawaMesh"], path: "Tests/WawaMeshTests"),

        // MARK: - WawaMap (MapLibre offline map rendering)
        .target(
            name: "WawaMap",
            dependencies: [.product(name: "MapLibre", package: "maplibre-gl-native-distribution")],
            path: "Sources/WawaMap"
        ),

        // MARK: - WawaNavigation (Ferrostar + Valhalla routing)
        .target(
            name: "WawaNavigation",
            dependencies: [
                .product(name: "FerrostarCore", package: "ferrostar"),
                .product(name: "FerrostarSwiftUI", package: "ferrostar"),
                .product(name: "FerrostarMapLibreUI", package: "ferrostar"),
            ],
            path: "Sources/WawaNavigation"
        ),

        // MARK: - App target
        .executableTarget(
            name: "WawaRideApp",
            dependencies: ["WawaMesh", "WawaMap", "WawaNavigation"],
            path: "Sources/WawaRideApp",
            resources: [.process("Resources")]
        ),
    ]
)
