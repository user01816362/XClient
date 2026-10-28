// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(name: "XKit", targets: ["XKit"]),
        .library(name: "XKitModels", targets: ["XKitModels"]),
        .library(name: "XKitTransport", targets: ["XKitTransport"]),
        .library(name: "XKitAuth", targets: ["XKitAuth"]),
        .library(name: "XKitAPI", targets: ["XKitAPI"]),
        .library(name: "XKitTesting", targets: ["XKitTesting"]),
        .executable(name: "XKitCLI", targets: ["XKitCLI"])
    ],
    targets: [
        // Core Value Types & Errors (Foundation only)
        .target(
            name: "XKitModels",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),

        // Network Transport Protocol & URLSession Implementation
        .target(
            name: "XKitTransport",
            dependencies: ["XKitModels"],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),

        // OAuth 2.0 PKCE & Token Lifecycle
        .target(
            name: "XKitAuth",
            dependencies: ["XKitModels", "XKitTransport"],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),

        // Typed X API v2 Endpoints
        .target(
            name: "XKitAPI",
            dependencies: ["XKitModels", "XKitTransport"],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),

        // Testing Mocks & Fixtures
        .target(
            name: "XKitTesting",
            dependencies: ["XKitModels", "XKitTransport"],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),

        // Top-level Umbrella Façade
        .target(
            name: "XKit",
            dependencies: ["XKitModels", "XKitTransport", "XKitAuth", "XKitAPI"],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),

        // macOS Command Line Interface / Verification Test Harness
        .executableTarget(
            name: "XKitCLI",
            dependencies: ["XKit", "XKitModels", "XKitTransport", "XKitAuth", "XKitAPI", "XKitTesting"],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(name: "XKitAPITests", dependencies: ["XKitAPI", "XKitModels", "XKitTransport", "XKitTesting"]),
        .testTarget(name: "XKitAuthTests", dependencies: ["XKitAuth"]),
        .testTarget(name: "XKitTransportTests", dependencies: ["XKitModels", "XKitTransport", "XKitTesting"])
    ]
)
