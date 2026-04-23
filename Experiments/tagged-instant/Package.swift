// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "tagged-instant",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../../../swift-tagged-primitives"),
    ],
    targets: [
        .executableTarget(
            name: "tagged-instant",
            dependencies: [
                .product(name: "Tagged Primitives", package: "swift-tagged-primitives"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        )
    ]
)
