// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "EnclaveKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(
            name: "EnclaveKitCore",
            targets: ["EnclaveKitCore"]
        ),
    ],
    targets: [
        .target(
            name: "EnclaveKitCore",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "EnclaveKitCoreTests",
            dependencies: ["EnclaveKitCore"],
            resources: [.copy("Vectors")],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ]
)
