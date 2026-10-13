// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SensveilBlurPoC",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PoCCore", targets: ["PoCCore"]),
        .library(name: "Sensveil", targets: ["Sensveil"]),
        .executable(name: "SensveilApp", targets: ["SensveilApp"]),
        .executable(name: "SensveilPoC", targets: ["SensveilPoC"]),
        .executable(name: "SensveilFixture", targets: ["SensveilFixture"])
    ],
    targets: [
        .target(name: "PoCCore"),
        .target(
            name: "Sensveil",
            dependencies: ["PoCCore"],
            resources: [.process("Resources")]
        ),
        .executableTarget(name: "SensveilApp", dependencies: ["Sensveil"]),
        .executableTarget(name: "SensveilPoC", dependencies: ["PoCCore"]),
        .executableTarget(name: "SensveilFixture"),
        .testTarget(name: "PoCCoreTests", dependencies: ["PoCCore"]),
        .testTarget(name: "SensveilTests", dependencies: ["Sensveil"])
    ]
)
