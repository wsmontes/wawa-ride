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
    ],
    targets: [
        .target(name: "WawaMesh", path: "Sources/WawaMesh"),
        .testTarget(name: "WawaMeshTests", dependencies: ["WawaMesh"], path: "Tests/WawaMeshTests"),

        .target(
            name: "WawaMap",
            dependencies: [.product(name: "MapLibre", package: "maplibre-gl-native-distribution")],
            path: "Sources/WawaMap"
        ),

        .target(
            name: "WawaNavigation",
            dependencies: [
                .product(name: "FerrostarCore", package: "ferrostar"),
                .product(name: "FerrostarSwiftUI", package: "ferrostar"),
                .product(name: "FerrostarMapLibreUI", package: "ferrostar"),
            ],
            path: "Sources/WawaNavigation"
        ),

        .executableTarget(
            name: "WawaRideApp",
            dependencies: ["WawaMesh", "WawaMap", "WawaNavigation"],
            path: "Sources/WawaRideApp",
            resources: [.process("Resources")]
        ),
    ]
)
