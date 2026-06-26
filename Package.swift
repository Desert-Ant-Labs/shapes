// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Shapes",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .macCatalyst(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "Shapes", targets: ["Shapes"]),
    ],
    targets: [
        .target(
            name: "Shapes",
            resources: [.copy("Resources/shapes.mlmodelc")]
        ),
        .testTarget(name: "ShapesTests", dependencies: ["Shapes"]),
    ]
)
