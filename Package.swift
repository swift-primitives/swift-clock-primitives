// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-clock-primitives",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(
            name: "Clock Primitives",
            targets: ["Clock Primitives"]
        ),
        .library(
            name: "Clock Primitives Test Support",
            targets: ["Clock Primitives Test Support"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-primitives/swift-tagged-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-carrier-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-standard-library-extensions.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "Clock Primitives",
            dependencies: [
                .product(name: "Tagged Primitives", package: "swift-tagged-primitives"),
                .product(name: "Carrier Primitives", package: "swift-carrier-primitives"),
                .product(name: "Standard Library Extensions", package: "swift-standard-library-extensions"),
            ]
        ),
        .target(
            name: "Clock Primitives Test Support",
            dependencies: [
                "Clock Primitives",
                .product(name: "Tagged Primitives Test Support", package: "swift-tagged-primitives"),
            ],
            path: "Tests/Support"
        ),
        .testTarget(
            name: "Clock Primitives Tests",
            dependencies: [
                "Clock Primitives",
                "Clock Primitives Test Support",
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("LifetimeDependence"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("LifetimeDependence"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
