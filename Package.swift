// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GlassCount",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "GlassCount", path: "Sources/GlassCount"),
        .testTarget(name: "GlassCountTests", dependencies: ["GlassCount"], path: "Tests/GlassCountTests"),
    ],
    swiftLanguageModes: [.v5]
)
