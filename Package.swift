// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "launchdx",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "launchdx", targets: ["launchdx"]),
        .library(name: "LaunchDXCore", targets: ["LaunchDXCore"])
    ],
    targets: [
        .target(
            name: "LaunchDXCore"
        ),
        .executableTarget(
            name: "launchdx",
            dependencies: ["LaunchDXCore"]
        ),
        .testTarget(
            name: "LaunchDXCoreTests",
            dependencies: ["LaunchDXCore"]
        )
    ]
)
