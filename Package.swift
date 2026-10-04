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
    ],
    targets: [
        .target(
            name: "EnclaveKit",
            swiftSettings: [enableUpcomingFeature],
        ),
        .testTarget(
            name: "EnclaveKitTests",
            dependencies: ["EnclaveKit"],
            resources: [.copy("Vectors")],
            swiftSettings: [enableUpcomingFeature],
        ),
    ]
)
