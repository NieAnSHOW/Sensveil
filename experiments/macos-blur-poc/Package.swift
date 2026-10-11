// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SensveilBlurPoC",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PoCCore", targets: ["PoCCore"])],
    targets: [
        .target(name: "PoCCore"),
        .testTarget(name: "PoCCoreTests", dependencies: ["PoCCore"])
    ]
)
