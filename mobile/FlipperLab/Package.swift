// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlipperLab",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "FlipperCore", targets: ["FlipperCore"])],
    targets: [
        .target(name: "ClassicRecovery"),
        .target(name: "FlipperCore", dependencies: ["ClassicRecovery"], resources: [.process("Resources")]),
        .testTarget(name: "FlipperCoreTests", dependencies: ["FlipperCore"])
    ]
)
