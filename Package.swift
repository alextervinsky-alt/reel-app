// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Reel",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ReelCore", targets: ["ReelCore"]),
        .executable(name: "Reel", targets: ["Reel"]),
    ],
    targets: [
        .target(name: "ReelCore"),
        .executableTarget(name: "Reel", dependencies: ["ReelCore"]),
        .testTarget(name: "ReelCoreTests", dependencies: ["ReelCore"], exclude: ["Fixtures"]),
    ],
    swiftLanguageModes: [.v5]
)
