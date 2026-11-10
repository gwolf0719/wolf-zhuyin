// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WolfZhuyin",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WolfEngine", targets: ["WolfEngine"]),
        .executable(name: "wolf", targets: ["wolf"]),
    ],
    targets: [
        .target(name: "WolfEngine"),
        .executableTarget(name: "wolf", dependencies: ["WolfEngine"]),
        .executableTarget(
            name: "WolfIME",
            dependencies: ["WolfEngine"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "WolfE2E",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "WolfEngineTests", dependencies: ["WolfEngine"]),
    ]
)
