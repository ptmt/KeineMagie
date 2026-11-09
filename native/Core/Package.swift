// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeineMagieCore",
    defaultLocalization: "de",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "KeineMagieCore", targets: ["KeineMagieCore"])],
    targets: [
        .target(name: "KeineMagieCore", resources: [.process("Resources")]),
        .testTarget(name: "KeineMagieCoreTests", dependencies: ["KeineMagieCore"])
    ]
)
