// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "tagged-instant",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../../../swift-identity-primitives"),
    ],
    targets: [
        .executableTarget(
            name: "tagged-instant",
            dependencies: [
                .product(name: "Identity Primitives", package: "swift-identity-primitives"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        )
    ]
)
