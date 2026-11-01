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
        .target(name: "IslandUI"),
        .target(name: "IslandKit", dependencies: ["IslandUI"]),
        .target(name: "IslandTestSupport"),
        .target(name: "ClaudeHookCore"),
        .target(name: "ClaudeLiveKit", dependencies: ["IslandKit", "ClaudeHookCore"]),
        .executableTarget(name: "ClaudeHook", dependencies: ["ClaudeHookCore"]),
        .target(name: "ShellKit", dependencies: ["IslandKit", "IslandUI", "SettingsKit", "ClaudeLiveKit"]),

        // Features: one module per lane, disjoint write surfaces.
        // Fan control: pure shared policy + XPC contract, the root helper, and the UI client.
        .target(name: "FanShared", path: "Sources/FanShared"),
        .executableTarget(name: "FanHelper", dependencies: ["FanShared"], path: "Sources/FanHelper"),
        .target(name: "FansFeature", dependencies: ["IslandKit", "FanShared"], path: "Sources/Features/Fans"),
        .target(name: "MonitorFeature", dependencies: ["IslandKit"], path: "Sources/Features/Monitor"),
        .target(name: "CommandBarFeature", dependencies: ["IslandKit", "IslandUI"], path: "Sources/Features/CommandBar"),
        .target(name: "TerminalFeature", dependencies: [
            "IslandKit", .product(name: "SwiftTerm", package: "SwiftTerm"),
        ], path: "Sources/Features/Terminal"),
        .target(name: "AgentsFeature", dependencies: ["IslandKit", "IslandUI", "ClaudeLiveKit"], path: "Sources/Features/Agents"),
        .target(name: "ClipboardFeature", dependencies: ["IslandKit"], path: "Sources/Features/Clipboard"),
        .target(name: "ShelfFeature", dependencies: ["IslandKit"], path: "Sources/Features/Shelf"),
        .target(name: "KeepAwakeFeature", dependencies: ["IslandKit", "IslandUI", "PortKit"], path: "Sources/Features/KeepAwake"),
        .target(name: "NowPlayingFeature", dependencies: ["IslandKit"], path: "Sources/Features/NowPlaying"),
        .target(name: "FinderFeature", dependencies: ["IslandKit", "IslandUI"], path: "Sources/Features/Finder"),
        .target(name: "DockFeature", dependencies: ["IslandKit"], path: "Sources/Features/Dock"),
        .target(name: "DisplayFeature", dependencies: ["IslandKit"], path: "Sources/Features/Display"),
        .target(name: "AudioFeature", dependencies: ["IslandKit", "PortKit"], path: "Sources/Features/Audio"),

        // Vorssaint port (GPL-3.0-or-later): one target, upstream layout kept, inert until a Bridge lane binds it.
        .systemLibrary(name: "HIDEventSystem", path: "Sources/HIDEventSystem"),
        .systemLibrary(name: "VMStatisticsCompat", path: "Sources/VMStatisticsCompat"),
        .target(name: "PortKit", dependencies: ["IslandKit", "IslandUI", "HIDEventSystem", "VMStatisticsCompat"], path: "Sources/PortKit"),

        .executableTarget(name: "MacIsland", dependencies: [
            "PortKit",
            "IslandKit", "IslandUI", "ShellKit", "ClaudeLiveKit", "SettingsKit", "TerminalFeature", "AgentsFeature", "ClipboardFeature",
            "ShelfFeature", "KeepAwakeFeature", "NowPlayingFeature",
            "FansFeature", "MonitorFeature", "CommandBarFeature",
            "FinderFeature", "DockFeature", "DisplayFeature", "AudioFeature",
        ]),
        .executableTarget(name: "mac-island-migrate", dependencies: ["SettingsKit"]),

        // ShellKit joins here only so the foundation tests can drive a real FeatureRegistry (kill switch, permission
        // grant) through PortFeatureBinding; PortKit itself still does not depend on ShellKit.
        .testTarget(name: "PortKitTests", dependencies: ["PortKit", "ShellKit", "IslandKit", "IslandTestSupport"]),
        .testTarget(name: "SettingsKitTests", dependencies: ["SettingsKit"]),
        .testTarget(name: "IslandKitTests", dependencies: ["IslandKit"]),
        .testTarget(name: "IslandUITests", dependencies: ["IslandUI", "IslandTestSupport"]),
        .testTarget(name: "ShellKitTests", dependencies: ["ShellKit", "IslandTestSupport"]),
        .testTarget(name: "ClaudeLiveKitTests", dependencies: ["ClaudeLiveKit", "IslandTestSupport"]),
        .testTarget(name: "ActivityTests", dependencies: ["IslandKit", "IslandTestSupport"]),
        .testTarget(name: "TerminalFeatureTests", dependencies: ["TerminalFeature"], path: "Tests/TerminalTests"),
        .testTarget(name: "AgentsFeatureTests", dependencies: ["AgentsFeature"], path: "Tests/AgentsTests"),
        .testTarget(name: "ClipboardFeatureTests", dependencies: ["ClipboardFeature"], path: "Tests/ClipboardTests"),
        .testTarget(name: "FanSharedTests", dependencies: ["FanShared"], path: "Tests/FanSharedTests"),
        .testTarget(name: "FansFeatureTests", dependencies: ["FansFeature"], path: "Tests/FansTests"),
        .testTarget(name: "MonitorFeatureTests", dependencies: ["MonitorFeature"], path: "Tests/MonitorTests"),
        .testTarget(name: "CommandBarFeatureTests", dependencies: ["CommandBarFeature"], path: "Tests/CommandBarTests"),
        .testTarget(name: "ShelfFeatureTests", dependencies: ["ShelfFeature"], path: "Tests/ShelfTests"),
        .testTarget(name: "KeepAwakeFeatureTests", dependencies: ["KeepAwakeFeature", "PortKit"], path: "Tests/KeepAwakeTests"),
        .testTarget(name: "NowPlayingFeatureTests", dependencies: ["NowPlayingFeature"], path: "Tests/NowPlayingTests"),
        .testTarget(name: "FinderFeatureTests", dependencies: ["FinderFeature"], path: "Tests/FinderTests"),
        .testTarget(name: "DockFeatureTests", dependencies: ["DockFeature"], path: "Tests/DockTests"),
        .testTarget(name: "DisplayFeatureTests", dependencies: ["DisplayFeature"], path: "Tests/DisplayTests"),
        .testTarget(name: "AudioFeatureTests", dependencies: ["AudioFeature"], path: "Tests/AudioTests"),
    ]
)
