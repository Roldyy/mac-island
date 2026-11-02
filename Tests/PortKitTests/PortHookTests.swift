import Foundation
import Testing
@testable import PortKit

/// The guard of "certains boutons marchent pas": every door the ported code leaves open for the host is either bound by
/// the app delegate or listed, with its reason, in `PortHookCatalog.allowlist`. A new hook (or a new do-nothing stub) that
/// is in neither fails here, so it is decided on purpose instead of shipping as a button that does nothing.
/// Source scans read the repository files next to this test (`#filePath`).
@MainActor
@Suite(.serialized) struct PortHookTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func source(_ path: String) -> String {
        (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
    }

    /// Where the host-facing doors are declared.
    static let hookFiles = [
        "Sources/PortKit/Compat/AppDelegate.swift", "Sources/PortKit/Compat/PortHost.swift",
        "Sources/PortKit/Compat/StatusItemController.swift", "Sources/PortKit/Compat/UpdateStubs.swift",
        "Sources/PortKit/Compat/ShareStubs.swift", "Sources/PortKit/Compat/AgentPriceSource.swift",
        "Sources/PortKit/Bridge/PortHostState.swift", "Sources/PortKit/Bridge/Dock.swift",
        "Sources/PortKit/Bridge/CaptureTools.swift", "Sources/PortKit/Bridge/PortDockCommands.swift",
        "Sources/PortKit/Bridge/IslandLockScreen.swift",
    ]

    static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// `var name: (...)?` (an optional closure) and `static var name: @MainActor () -> Void = {}` (a closure with a do-nothing
    /// default): the two shapes a hook takes.
    static func hookNames(in text: String) -> [String] {
        matches(#"^\s*(?:(?:public|internal|private|@MainActor|nonisolated\(unsafe\)|static) )*var (\w+): \(?(?:@MainActor |@Sendable )*\(.*\) *-> *[\w?]+\)?\? *(?:=.*)?$"#, in: text)
            + matches(#"^\s*(?:(?:public|@MainActor|static) )*var (\w+): @MainActor \(\) -> (?:Void|Bool) = \{"#, in: text)
    }

    /// `func name(...) {}`: a stub whose body is empty.
    static func emptyStubNames(in text: String) -> [String] {
        matches(#"func (\w+)\((?:[^()]|\(\))*\)(?: -> [^{]+)? *\{ *\}"#, in: text)
    }

    static var allHookNames: Set<String> {
        var names = Set<String>()
        for file in hookFiles { names.formUnion(hookNames(in: source(file))) }
        return names
    }

    static var bound: Set<String> { Set(PortHookCatalog.bound.map(\.name)) }
    static var allowed: Set<String> { Set(PortHookCatalog.allowlist.keys) }

    @Test func theScanFindsTheHooksItIsMeantToGuard() {
        // A scan that silently finds nothing would pass forever: pin what it must see.
        let names = Self.allHookNames
        for expected in ["openSettings", "closePanel", "relaunch", "isOverMenuBarItem", "openSettingsPage", "openFeedback",
                         "openIslandTab", "closeIsland", "reshowIcon", "setEnabled", "storedSwitch", "availability",
                         "requestPermission", "clipboardIsOn", "context", "perform"] {
            #expect(names.contains(expected), "the hook scan no longer sees \(expected)")
        }
    }

    @Test func everyHookIsBoundByTheAppOrAllowedWithAReason() {
        let unknown = Self.allHookNames.subtracting(Self.bound).subtracting(Self.allowed)
        #expect(unknown.isEmpty, "unbound hook(s) with no decision: \(unknown.sorted()). Bind them in AppDelegate (and list them in PortHookCatalog.bound) or add them to the allowlist with a reason.")
    }

    @Test func everyDoNothingStubIsListedWithItsReason() {
        var stubs = Set<String>()
        for file in Self.hookFiles where file.contains("/Compat/") { stubs.formUnion(Self.emptyStubNames(in: Self.source(file))) }
        let unknown = stubs.subtracting(Self.allowed)
        #expect(unknown.isEmpty, "empty stub(s) a button may reach: \(unknown.sorted()). Implement them or allowlist them with a reason.")
        #expect(stubs.contains("showUpdatePreview"), "the stub scan no longer sees the known stubs")
    }

    @Test func theAllowlistIsHonest() {
        for (name, reason) in PortHookCatalog.allowlist {
            #expect(reason.count > 20, "\(name): a reason, not a word")
            #expect(!Self.bound.contains(name), "\(name) is both bound and allowed")
            #expect(Self.allHookNames.contains(name) || Self.compatText.contains(name), "\(name) no longer exists: drop it from the allowlist")
        }
        for entry in PortHookCatalog.bound {
            #expect(Self.allHookNames.contains(entry.name), "\(entry.name) is no longer declared: drop it from PortHookCatalog.bound")
        }
    }

    static var compatText: String { hookFiles.map(source).joined(separator: "\n") }

    @Test func theAppDelegateBindsEveryHookTheCatalogSaysItBinds() {
        let app = Self.source("Sources/MacIsland/AppDelegate.swift")
        #expect(!app.isEmpty)
        for entry in PortHookCatalog.bound {
            #expect(app.contains(entry.door), "AppDelegate no longer binds \(entry.name) (looked for `\(entry.door)`)")
        }
    }

    @Test func installingTheFullHostLeavesNoFacadeHookUnbound() {
        let previous = AppDelegate.current
        defer { AppDelegate.current = previous }
        AppDelegate.current = nil
        PortBridge.install(host: PortBridge.Host(openSettings: {}, closePanel: {}, relaunch: {}, openSettingsPage: { _ in }, openFeedback: { _ in }))
        #expect(PortBridge.unboundHooks == ["openIslandTab", "closeIsland", "reshowIcon"], "the island and the icon bind later")
        PortBridge.connectIsland(openTab: { _ in }, close: {})
        PortBridge.connectMenuBar(showIcon: {})
        #expect(PortBridge.unboundHooks.isEmpty)
    }

    @Test func aHostThatForgetsADoorIsReported() {
        let previous = AppDelegate.current
        defer { AppDelegate.current = previous }
        AppDelegate.current = nil
        PortBridge.install(host: PortBridge.Host(openSettings: {}))
        PortBridge.connectIsland(openTab: { _ in }, close: {})
        PortBridge.connectMenuBar(showIcon: {})
        #expect(PortBridge.unboundHooks == ["openSettingsPage", "openFeedback"], "the unbound doors are named")
    }

    @Test func theRelaunchDoorMayStayNilOutsideABundle() {
        #expect(PortHookCatalog.bound.first { $0.name == "relaunch" }?.optional == true)
    }
}
