// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeineMagieCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "KeineMagieCore", targets: ["KeineMagieCore"])],
    targets: [
        .target(name: "KeineMagieCore"),
        .testTarget(name: "KeineMagieCoreTests", dependencies: ["KeineMagieCore"])
    ]
)
