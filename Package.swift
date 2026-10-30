// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacIsland",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SettingsKit", targets: ["SettingsKit"]),
    ],
    targets: [
        .target(name: "SettingsKit"),
        .executableTarget(name: "mac-island-migrate", dependencies: ["SettingsKit"]),
        .testTarget(name: "SettingsKitTests", dependencies: ["SettingsKit"]),
    ]
)
