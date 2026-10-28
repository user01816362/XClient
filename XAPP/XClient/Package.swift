// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XClient",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        // Multiplatform library target exposing core views, view models, and mock stores
        .library(
            name: "XClient",
            targets: ["XClient"]
        ),
        // macOS executable target for local execution and automated verification
        .executable(
            name: "XClientApp",
            targets: ["XClientApp"]
        )
    ],
    dependencies: [
        // Local path dependency to the verified XKit SDK
        .package(path: "../../sdks/XKit")
    ],
    targets: [
        // 1. Shared Multiplatform SwiftUI Client Library
        .target(
            name: "XClient",
            dependencies: [
                .product(name: "XKit", package: "XKit"),
                .product(name: "XKitModels", package: "XKit"),
                .product(name: "XKitTransport", package: "XKit"),
                .product(name: "XKitAuth", package: "XKit"),
                .product(name: "XKitAPI", package: "XKit"),
                .product(name: "XKitTesting", package: "XKit")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),

        // 2. macOS Desktop Executable Runner (Interactive UI & Headless Verification)
        .executableTarget(
            name: "XClientApp",
            dependencies: [
                "XClient",
                .product(name: "XKit", package: "XKit"),
                .product(name: "XKitTesting", package: "XKit")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),

        // 3. Automated Test Suite Target
        .testTarget(
            name: "XClientTests",
            dependencies: [
                "XClient",
                .product(name: "XKit", package: "XKit"),
                .product(name: "XKitTesting", package: "XKit")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
