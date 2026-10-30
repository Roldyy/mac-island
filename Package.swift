// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacIsland",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SettingsKit", targets: ["SettingsKit"]),
    ],
    dependencies: [
        // MIT. Pinned exactly: the terminal is the one place a dependency upgrade can break typing.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.20.0"),
    ],
    targets: [
        .target(name: "SettingsKit"),
        .target(name: "IslandKit"),

        // Features: one module per lane, disjoint write surfaces.
        .target(name: "TerminalFeature", dependencies: [
            "IslandKit", .product(name: "SwiftTerm", package: "SwiftTerm"),
        ], path: "Sources/Features/Terminal"),
        .target(name: "AgentsFeature", dependencies: ["IslandKit"], path: "Sources/Features/Agents"),
        .target(name: "ClipboardFeature", dependencies: ["IslandKit"], path: "Sources/Features/Clipboard"),

        .executableTarget(name: "MacIsland", dependencies: [
            "IslandKit", "SettingsKit", "TerminalFeature", "AgentsFeature", "ClipboardFeature",
        ]),
        .executableTarget(name: "mac-island-migrate", dependencies: ["SettingsKit"]),

        .testTarget(name: "SettingsKitTests", dependencies: ["SettingsKit"]),
        .testTarget(name: "IslandKitTests", dependencies: ["IslandKit"]),
        .testTarget(name: "TerminalFeatureTests", dependencies: ["TerminalFeature"], path: "Tests/TerminalTests"),
        .testTarget(name: "AgentsFeatureTests", dependencies: ["AgentsFeature"], path: "Tests/AgentsTests"),
        .testTarget(name: "ClipboardFeatureTests", dependencies: ["ClipboardFeature"], path: "Tests/ClipboardTests"),
    ]
)
