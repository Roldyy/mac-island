// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacIsland",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SettingsKit", targets: ["SettingsKit"]),
        // Lane W8A: libMacIslandNowPlaying.dylib. Never linked into the app: now-playing.pl loads it into /usr/bin/perl
        // (a platform binary, the only process MediaRemote still answers since macOS 15.4). bundle.sh copies and signs it.
        .library(name: "MacIslandNowPlaying", type: .dynamic, targets: ["NowPlayingAdapter"]),
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
        .target(name: "CommandBarFeature", dependencies: ["IslandKit", "IslandUI", "PortKit"], path: "Sources/Features/CommandBar"),
        .target(name: "TerminalFeature", dependencies: [
            "IslandKit", "IslandUI", .product(name: "SwiftTerm", package: "SwiftTerm"),
        ], path: "Sources/Features/Terminal"),
        .target(name: "AgentsFeature", dependencies: ["IslandKit", "IslandUI", "ClaudeLiveKit"], path: "Sources/Features/Agents"),
        .target(name: "ClipboardFeature", dependencies: ["IslandKit"], path: "Sources/Features/Clipboard"),
        .target(name: "ShelfFeature", dependencies: ["IslandKit", "PortKit"], path: "Sources/Features/Shelf"),
        .target(name: "KeepAwakeFeature", dependencies: ["IslandKit", "IslandUI", "PortKit"], path: "Sources/Features/KeepAwake"),
        .target(name: "NowPlayingFeature", dependencies: ["IslandKit"], path: "Sources/Features/NowPlaying"),
        .target(name: "FinderFeature", dependencies: ["IslandKit", "IslandUI"], path: "Sources/Features/Finder"),
        .target(name: "DockFeature", dependencies: ["IslandKit", "PortKit"], path: "Sources/Features/Dock"),
        .target(name: "AudioFeature", dependencies: ["IslandKit", "PortKit"], path: "Sources/Features/Audio"),
        // IP scanner: Network.framework + getifaddrs + SystemConfiguration only, no PortKit, nothing depends on it but the app.
        // ShellKit joins only for the "Adresse IP" status chip (IPChipSource implements ShellKit's StatusChipSource).
        .target(name: "IPScannerFeature", dependencies: ["IslandKit", "IslandUI", "ShellKit"], path: "Sources/Features/IPScanner"),
        // Default apps: LaunchServices (NSWorkspace) + Info.plist reading only; every write goes through one facade, nothing depends on it but the app.
        .target(name: "DefaultAppsFeature", dependencies: ["IslandKit", "IslandUI"], path: "Sources/Features/DefaultApps"),

        // Vorssaint port (GPL-3.0-or-later): one target, upstream layout kept, inert until a Bridge lane binds it.
        .systemLibrary(name: "HIDEventSystem", path: "Sources/HIDEventSystem"),
        .systemLibrary(name: "VMStatisticsCompat", path: "Sources/VMStatisticsCompat"),
        // The one place that touches MediaRemote's private symbols (lane W8A); AppKit and Foundation only.
        .target(name: "NowPlayingAdapter", path: "Sources/NowPlayingAdapter"),
        // FansFeature: the Fans bridge drives the helper through its `FanDriving` door (no dependency the other way).
        .target(name: "PortKit", dependencies: ["IslandKit", "IslandUI", "FansFeature", "HIDEventSystem", "VMStatisticsCompat"], path: "Sources/PortKit"),

        .executableTarget(name: "MacIsland", dependencies: [
            "PortKit",
            "IslandKit", "IslandUI", "ShellKit", "ClaudeLiveKit", "SettingsKit", "TerminalFeature", "AgentsFeature", "ClipboardFeature",
            "ShelfFeature", "KeepAwakeFeature", "NowPlayingFeature",
            "FansFeature", "MonitorFeature", "CommandBarFeature",
            "FinderFeature", "DockFeature", "AudioFeature", "IPScannerFeature", "DefaultAppsFeature",
        ]),
        .executableTarget(name: "mac-island-migrate", dependencies: ["SettingsKit"]),

        // ShellKit joins here only so the foundation tests can drive a real FeatureRegistry (kill switch, permission
        // grant) through PortFeatureBinding; PortKit itself still does not depend on ShellKit.
        .testTarget(name: "PortKitTests", dependencies: ["PortKit", "FansFeature", "ShellKit", "IslandKit", "IslandTestSupport"]),
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
        .testTarget(name: "ShelfFeatureTests", dependencies: ["ShelfFeature", "PortKit"], path: "Tests/ShelfTests"),
        .testTarget(name: "KeepAwakeFeatureTests", dependencies: ["KeepAwakeFeature", "PortKit"], path: "Tests/KeepAwakeTests"),
        .testTarget(name: "NowPlayingFeatureTests", dependencies: ["NowPlayingFeature"], path: "Tests/NowPlayingTests"),
        .testTarget(name: "FinderFeatureTests", dependencies: ["FinderFeature"], path: "Tests/FinderTests"),
        .testTarget(name: "DockFeatureTests", dependencies: ["DockFeature"], path: "Tests/DockTests"),
        .testTarget(name: "AudioFeatureTests", dependencies: ["AudioFeature"], path: "Tests/AudioTests"),
        // ShellKit joins only to check the registration (descriptor off by default, kill switch stops the feature).
        .testTarget(name: "IPScannerFeatureTests", dependencies: ["IPScannerFeature", "ShellKit", "IslandKit", "IslandTestSupport"], path: "Tests/IPScannerTests"),
        // ShellKit joins only to check the registration (descriptor off by default, kill switch stops the feature, page and tile exist).
        .testTarget(name: "DefaultAppsFeatureTests", dependencies: ["DefaultAppsFeature", "ShellKit", "SettingsKit", "IslandKit", "IslandTestSupport"], path: "Tests/DefaultAppsTests"),
    ]
)
