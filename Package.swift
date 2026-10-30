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
        // Fan control: pure shared policy + XPC contract, the root helper, and the UI client.
        .target(name: "FanShared", path: "Sources/FanShared"),
        .executableTarget(name: "FanHelper", dependencies: ["FanShared"], path: "Sources/FanHelper"),
        .target(name: "FansFeature", dependencies: ["IslandKit", "FanShared"], path: "Sources/Features/Fans"),
        .target(name: "MonitorFeature", dependencies: ["IslandKit"], path: "Sources/Features/Monitor"),
        .target(name: "CommandBarFeature", dependencies: ["IslandKit"], path: "Sources/Features/CommandBar"),
        .target(name: "TerminalFeature", dependencies: [
            "IslandKit", .product(name: "SwiftTerm", package: "SwiftTerm"),
        ], path: "Sources/Features/Terminal"),
        .target(name: "AgentsFeature", dependencies: ["IslandKit"], path: "Sources/Features/Agents"),
        .target(name: "ClipboardFeature", dependencies: ["IslandKit"], path: "Sources/Features/Clipboard"),
        .target(name: "ShelfFeature", dependencies: ["IslandKit"], path: "Sources/Features/Shelf"),
        .target(name: "KeepAwakeFeature", dependencies: ["IslandKit"], path: "Sources/Features/KeepAwake"),
        .target(name: "NowPlayingFeature", dependencies: ["IslandKit"], path: "Sources/Features/NowPlaying"),
        .target(name: "FinderFeature", dependencies: ["IslandKit"], path: "Sources/Features/Finder"),
        .target(name: "DockFeature", dependencies: ["IslandKit"], path: "Sources/Features/Dock"),
        .target(name: "DisplayFeature", dependencies: ["IslandKit"], path: "Sources/Features/Display"),
        .target(name: "AudioFeature", dependencies: ["IslandKit"], path: "Sources/Features/Audio"),

        .executableTarget(name: "MacIsland", dependencies: [
            "IslandKit", "SettingsKit", "TerminalFeature", "AgentsFeature", "ClipboardFeature",
            "ShelfFeature", "KeepAwakeFeature", "NowPlayingFeature",
            "FansFeature", "MonitorFeature", "CommandBarFeature",
            "FinderFeature", "DockFeature", "DisplayFeature", "AudioFeature",
        ]),
        .executableTarget(name: "mac-island-migrate", dependencies: ["SettingsKit"]),

        .testTarget(name: "SettingsKitTests", dependencies: ["SettingsKit"]),
        .testTarget(name: "IslandKitTests", dependencies: ["IslandKit"]),
        .testTarget(name: "TerminalFeatureTests", dependencies: ["TerminalFeature"], path: "Tests/TerminalTests"),
        .testTarget(name: "AgentsFeatureTests", dependencies: ["AgentsFeature"], path: "Tests/AgentsTests"),
        .testTarget(name: "ClipboardFeatureTests", dependencies: ["ClipboardFeature"], path: "Tests/ClipboardTests"),
        .testTarget(name: "FanSharedTests", dependencies: ["FanShared"], path: "Tests/FanSharedTests"),
        .testTarget(name: "FansFeatureTests", dependencies: ["FansFeature"], path: "Tests/FansTests"),
        .testTarget(name: "MonitorFeatureTests", dependencies: ["MonitorFeature"], path: "Tests/MonitorTests"),
        .testTarget(name: "CommandBarFeatureTests", dependencies: ["CommandBarFeature"], path: "Tests/CommandBarTests"),
        .testTarget(name: "ShelfFeatureTests", dependencies: ["ShelfFeature"], path: "Tests/ShelfTests"),
        .testTarget(name: "KeepAwakeFeatureTests", dependencies: ["KeepAwakeFeature"], path: "Tests/KeepAwakeTests"),
        .testTarget(name: "NowPlayingFeatureTests", dependencies: ["NowPlayingFeature"], path: "Tests/NowPlayingTests"),
        .testTarget(name: "FinderFeatureTests", dependencies: ["FinderFeature"], path: "Tests/FinderTests"),
        .testTarget(name: "DockFeatureTests", dependencies: ["DockFeature"], path: "Tests/DockTests"),
        .testTarget(name: "DisplayFeatureTests", dependencies: ["DisplayFeature"], path: "Tests/DisplayTests"),
        .testTarget(name: "AudioFeatureTests", dependencies: ["AudioFeature"], path: "Tests/AudioTests"),
    ]
)
