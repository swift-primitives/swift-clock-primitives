// swift-tools-version: 6.3

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
        )
    ],
    dependencies: [
        .package(path: "../swift-identity-primitives"),
        .package(path: "../swift-standard-library-extensions"),
        .package(path: "../swift-witness-primitives"),
    ],
    targets: [
        .target(
            name: "Clock Primitives",
            dependencies: [
                .product(name: "Identity Primitives", package: "swift-identity-primitives"),
                .product(name: "Standard Library Extensions", package: "swift-standard-library-extensions"),
                .product(name: "Witness Primitives", package: "swift-witness-primitives"),
            ]
        ),
        .testTarget(
            name: "Clock Primitives Tests",
            dependencies: [
                "Clock Primitives"
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
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
