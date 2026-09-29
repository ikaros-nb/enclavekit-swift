// swift-tools-version: 6.4

import PackageDescription

let enableUpcomingFeature = SwiftSetting.enableUpcomingFeature("ApproachableConcurrency")

let package = Package(
    name: "EnclaveKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(
            name: "EnclaveKit",
            targets: ["EnclaveKit"]
        ),
        .library(
            name: "EnclaveKitCore",
            targets: ["EnclaveKitCore"]
        ),
    ],
    targets: [
        .target(
            name: "EnclaveKit",
            dependencies: ["EnclaveKitCore"],
            swiftSettings: [enableUpcomingFeature],
        ),
        .target(
            name: "EnclaveKitCore",
            swiftSettings: [enableUpcomingFeature],
        ),
        .testTarget(
            name: "EnclaveKitTests",
            dependencies: ["EnclaveKit"],
            swiftSettings: [enableUpcomingFeature],
        ),
        .testTarget(
            name: "EnclaveKitCoreTests",
            dependencies: ["EnclaveKitCore"],
            resources: [.copy("Vectors")],
            swiftSettings: [enableUpcomingFeature],
        ),
    ]
)
