import Foundation
import Testing
@testable import PortKit

/// Upstream ran its crash-recovery and re-exec cleanup entry points from main.swift and the app delegate; the
/// first import dropped them silently. A `recover*` / `runIfRequested*` function nobody calls is a system
/// change that is never given back, so every one needs a call site in Bridge/ or MacIsland (a private one: in
/// its own file).
@Suite struct RecoveryEntryPointTests {
    private struct Declaration { let name: String; let file: String; let isPrivate: Bool }

    private static var macIslandSources: URL {
        PortSourceScrubTests.repoRoot.appendingPathComponent("Sources/MacIsland")
    }

    private static func swiftFiles(under root: URL) -> [(path: String, text: String)] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var result: [(String, String)] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            if let text = try? String(contentsOf: url, encoding: .utf8) { result.append((url.path, text)) }
        }
        return result
    }

    private static let declaration = try! NSRegularExpression(
        pattern: #"func ((?:recover[A-Z]|runIfRequested)\w*)\s*\("#)

    private static func declarations() -> [Declaration] {
        var found: [Declaration] = []
        for file in PortSourceScrubTests.files where !file.path.hasPrefix("Bridge/") {
            for line in file.lines {
                let text = String(line)
                let range = NSRange(text.startIndex..., in: text)
                guard let match = declaration.firstMatch(in: text, range: range),
                      let nameRange = Range(match.range(at: 1), in: text) else { continue }
                found.append(Declaration(name: String(text[nameRange]), file: file.path,
                                         isPrivate: text.contains("private ")))
            }
        }
        return found
    }

    /// Lines that call `name(` and do not declare it.
    private static func callLines(of name: String, in text: String) -> Int {
        text.split(separator: "\n").filter {
            !$0.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("//")
                && $0.contains("\(name)(") && !$0.contains("func \(name)")
        }.count
    }

    @Test func theKeptSourcesHaveRecoveryEntryPoints() {
        let names = Set(Self.declarations().map(\.name))
        for expected in ["recoverIfNeeded", "recoverPendingAtLaunch", "runIfRequestedAndExit"] {
            #expect(names.contains(expected), "\(expected) vanished: update the scan before trusting it")
        }
    }

    @Test func everyRecoveryEntryPointHasACaller() {
        let declarations = Self.declarations()
        let bridge = PortSourceScrubTests.files.filter { $0.path.hasPrefix("Bridge/") }
            .map { $0.lines.joined(separator: "\n") }
        let host = Self.swiftFiles(under: Self.macIslandSources).map(\.text)
        let callerText = (bridge + host).joined(separator: "\n")

        var missing: [String] = []
        for name in Set(declarations.map(\.name)).sorted() {
            let public_ = declarations.filter { $0.name == name && !$0.isPrivate }
            // Same name on several types: one call line per declaration (4x recoverIfNeeded, 2x guards).
            if Self.callLines(of: name, in: callerText) < public_.count {
                missing.append("\(name): \(public_.count) declaration(s), \(Self.callLines(of: name, in: callerText)) call line(s) in Bridge/MacIsland")
            }
            for local in declarations.filter({ $0.name == name && $0.isPrivate }) {
                let text = PortSourceScrubTests.files.first { $0.path == local.file }?
                    .lines.joined(separator: "\n") ?? ""
                if Self.callLines(of: name, in: text) == 0 { missing.append("\(name) (private, \(local.file)) is never called") }
            }
        }
        #expect(missing.isEmpty, "recovery entry point without a caller: \(missing)")
    }

    @Test func recoveryStepOnlyEntersStepsWhoseMarkerIsSet() {
        let name = "mis-tests-recovery-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        defer { suite.removePersistentDomain(forName: name) }
        #expect(PortBridge.RecoveryPlan(defaults: suite) == PortBridge.RecoveryPlan(defaults: UserDefaults(suiteName: name + "-empty")!))
        let none = PortBridge.RecoveryPlan(defaults: suite)
        #expect(!none.keepAwake && !none.systemShortcuts && !none.fanControl)

        suite.set(true, forKey: DefaultsKey.fanControlRecoveryNeeded)
        suite.set([3, 4], forKey: DefaultsKey.systemShortcutsSuppressed)
        suite.set(true, forKey: DefaultsKey.sleepDisabledFlag)
        let all = PortBridge.RecoveryPlan(defaults: suite)
        #expect(all.keepAwake && all.systemShortcuts && all.fanControl)
    }
}
