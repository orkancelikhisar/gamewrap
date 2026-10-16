// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GameWrap",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GameWrapCore", targets: ["GameWrapCore"]),
        .executable(name: "GameWrap", targets: ["GameWrapApp"]),
    ],
    targets: [
        .target(name: "GameWrapCore", resources: [.process("Resources")]),
        .executableTarget(name: "GameWrapApp", dependencies: ["GameWrapCore"]),
        .testTarget(name: "GameWrapCoreTests", dependencies: ["GameWrapCore"]),
        .testTarget(name: "GameWrapAppTests", dependencies: ["GameWrapApp"]),
    ]
)
