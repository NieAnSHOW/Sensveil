// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SensveilBlurPoC",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PoCCore", targets: ["PoCCore"]),
        .executable(name: "SensveilPoC", targets: ["SensveilPoC"]),
        .executable(name: "SensveilFixture", targets: ["SensveilFixture"])
    ],
    targets: [
        .target(name: "PoCCore"),
        .executableTarget(name: "SensveilPoC", dependencies: ["PoCCore"]),
        .executableTarget(name: "SensveilFixture"),
        .testTarget(name: "PoCCoreTests", dependencies: ["PoCCore"])
    ]
)
