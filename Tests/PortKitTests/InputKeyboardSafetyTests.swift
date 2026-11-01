import Foundation
import Testing
@testable import PortKit

/// Lane W1-C safety: a keyboard feature that misbehaves can lock the user out, so the ways back are pinned here.
/// The real `hidutil` and the real event taps are never touched: `hidutil` is a fake table, the taps are checked
/// as source contracts (a tap callback cannot be driven without Accessibility and a real keyboard).
@MainActor
@Suite(.serialized) struct InputKeyboardSafetyTests {
    // MARK: A fake hidutil

    private static let ours = SuperKeyMapping(source: SuperKeySource.capsLock.usage, destination: SuperKeySupport.triggerUsage)
    private static let foreign = SuperKeyMapping(source: SuperKeySource.rightCommand.usage,
                                                 destination: SuperKeySource.rightOption.usage)

    /// One mapping table per keyboard, answering `property --get` like hidutil and taking `--set`.
    private final class FakeHID: @unchecked Sendable {
        private let lock = NSLock()
        private var tables: [[SuperKeyMapping]]
        private(set) var calls: [[String]] = []
        var failGet = false
        /// `--set` answers success but changes nothing (a keyboard that refuses the table).
        var ignoreSet = false

        init(tables: [[SuperKeyMapping]]) { self.tables = tables }

        var current: [[SuperKeyMapping]] { lock.lock(); defer { lock.unlock() }; return tables }
        var sets: [[String]] { calls.filter { $0.contains("--set") } }

        func run(_ arguments: [String]) -> (status: Int32, output: String) {
            lock.lock()
            defer { lock.unlock() }
            calls.append(arguments)
            if let index = arguments.firstIndex(of: "--set"), arguments.indices.contains(index + 1) {
                if !ignoreSet { tables = tables.map { _ in Self.parse(arguments[index + 1]) } }
                return (0, "")
            }
            if failGet { return (1, "") }
            return (0, Self.report(tables))
        }

        static func parse(_ argument: String) -> [SuperKeyMapping] {
            guard let data = argument.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = root["UserKeyMapping"] as? [[String: Any]] else { return [] }
            return entries.compactMap {
                guard let src = ($0["HIDKeyboardModifierMappingSrc"] as? NSNumber)?.uint64Value,
                      let dst = ($0["HIDKeyboardModifierMappingDst"] as? NSNumber)?.uint64Value else { return nil }
                return SuperKeyMapping(source: src, destination: dst)
            }
        }

        static func report(_ tables: [[SuperKeyMapping]]) -> String {
            var text = "Matching Service Property:\n"
            for (index, table) in tables.enumerated() {
                text += "0x10000\(index)bb1 UserKeyMapping (\n"
                for mapping in table {
                    text += "    {\n        HIDKeyboardModifierMappingDst = \(mapping.destination);\n"
                    text += "        HIDKeyboardModifierMappingSrc = \(mapping.source);\n    }\n"
                }
                text += ")\n"
            }
            return text
        }
    }

    private func withFake(_ hid: FakeHID, _ body: () -> Void) {
        SuperKeyMappingGuard.runHIDOverride = { hid.run($0) }
        defer { SuperKeyMappingGuard.runHIDOverride = nil }
        body()
    }

    // MARK: The guard's restore path (what runs after a crash or a kill, in our own binary)

    @Test func theGuardCleanupRemovesOnlyTheSuperKeyEntry() {
        let hid = FakeHID(tables: [[Self.ours, Self.foreign]])
        withFake(hid) { #expect(SuperKeyMappingGuard.clear(source: .capsLock)) }
        #expect(hid.current == [[Self.foreign]], "the user's own mapping is kept, ours is gone")
        #expect(hid.sets.count == 1)
        #expect(hid.sets.first?.contains("--matching") == true && hid.sets.first?.contains("keyboard") == true)
        #expect(hid.sets.first?.last == SuperKeySupport.mappingArgument([Self.foreign]))
    }

    @Test func theGuardCleanupOnACleanTableWritesNothing() {
        let hid = FakeHID(tables: [[Self.foreign]])
        withFake(hid) { #expect(SuperKeyMappingGuard.clear(source: .capsLock)) }
        #expect(hid.sets.isEmpty)
    }

    @Test func theGuardCleanupClearsEveryKeyboardOfTheSameShape() {
        let hid = FakeHID(tables: [[Self.ours], [Self.ours]])
        withFake(hid) { #expect(SuperKeyMappingGuard.clear(source: .capsLock)) }
        #expect(hid.current == [[], []])
    }

    @Test func theGuardCleanupRefusesToCopyOneKeyboardsMappingOntoAnother() {
        let hid = FakeHID(tables: [[Self.ours, Self.foreign], [Self.ours]])
        withFake(hid) { #expect(!SuperKeyMappingGuard.clear(source: .capsLock)) }
        #expect(hid.sets.isEmpty, "different external tables are never merged")
    }

    @Test func theGuardCleanupReportsFailureWhenHidutilFailsOrDoesNotConfirm() {
        let failing = FakeHID(tables: [[Self.ours]])
        failing.failGet = true
        withFake(failing) { #expect(!SuperKeyMappingGuard.clear(source: .capsLock)) }

        let stubborn = FakeHID(tables: [[Self.ours]])
        stubborn.ignoreSet = true
        withFake(stubborn) { #expect(!SuperKeyMappingGuard.clear(source: .capsLock)) }
        #expect(stubborn.current == [[Self.ours]])
    }

    @Test func theCleanupArgumentIsParsedAndOurBinaryRunsItBeforeAnyApp() throws {
        #expect(SuperKeyMappingGuard.cleanupSource(in: ["MacIsland", SuperKeyMappingGuard.cleanupArgument, "capsLock"]) == .capsLock)
        #expect(SuperKeyMappingGuard.cleanupSource(in: ["MacIsland", SuperKeyMappingGuard.cleanupArgument, "nope"]) == nil)
        #expect(SuperKeyMappingGuard.cleanupSource(in: ["MacIsland"]) == nil)

        let main = try source("Sources/MacIsland/main.swift")
        let cleanup = try #require(main.range(of: "PortBridge.runCleanupFlagsIfRequested()"))
        let app = try #require(main.range(of: "NSApplication.shared"))
        #expect(cleanup.lowerBound < app.lowerBound, "the re-exec'd cleanup runs before NSApplication exists")
        #expect(try source("Sources/PortKit/Bridge/PortBridge.swift").contains("SuperKeyMappingGuard.runIfRequestedAndExit()"))
    }

    // MARK: stop() restores the mapping (through the service, with the fake)

    @Test func stoppingTheSuperKeyPutsTheMappingBack() {
        PortHostFixture.isolated { defaults in
            defaults.set(true, forKey: DefaultsKey.superKeyMappingApplied)
            defaults.set(SuperKeySource.capsLock.rawValue, forKey: DefaultsKey.superKeyMappedSource)
            let hid = FakeHID(tables: [[Self.ours, Self.foreign]])
            withFake(hid) { SuperKeyService.shared.suspend() }  // what the bound stop calls, synchronously
            #expect(hid.current == [[Self.foreign]], "Caps Lock is a real key again, the user's own mapping stays")
            #expect(!defaults.bool(forKey: DefaultsKey.superKeyMappingApplied))
            #expect(defaults.object(forKey: DefaultsKey.superKeyMappedSource) == nil)
            #expect(!SuperKeyService.shared.isRunning)
        }
    }

    @Test func aClearThatHidutilDoesNotConfirmKeepsTheMarkerSoTheNextLaunchRetries() {
        PortHostFixture.isolated { defaults in
            defaults.set(true, forKey: DefaultsKey.superKeyMappingApplied)
            defaults.set(SuperKeySource.capsLock.rawValue, forKey: DefaultsKey.superKeyMappedSource)
            let hid = FakeHID(tables: [[Self.ours]])
            hid.ignoreSet = true
            withFake(hid) { SuperKeyService.shared.suspend() }
            #expect(defaults.bool(forKey: DefaultsKey.superKeyMappingApplied), "still eligible for a retry")
        }
    }

    @Test func stoppingASuperKeyThatNeverAppliedAMappingTouchesNothing() {
        PortHostFixture.isolated { _ in
            let hid = FakeHID(tables: [[Self.foreign]])
            withFake(hid) { SuperKeyService.shared.suspend() }
            #expect(hid.calls.isEmpty, "no marker, no hidutil")
        }
    }

    // MARK: Pass-through

    @Test func theTapsHandEveryEventThroughWhenStoppedOrWhenASecureFieldHasFocus() {
        #expect(!KeyboardTapSafety.shouldPassThrough(featureAvailable: true, secureInputEnabled: false))
        #expect(KeyboardTapSafety.shouldPassThrough(featureAvailable: false, secureInputEnabled: false),
                "kill switch, safe mode, quarantine, lost permission")
        #expect(KeyboardTapSafety.shouldPassThrough(featureAvailable: true, secureInputEnabled: true),
                "a password field: nothing typed there is held, dropped or rewritten")
        #expect(KeyboardTapSafety.shouldPassThrough(featureAvailable: false, secureInputEnabled: true))
    }

    /// The text of one upstream file with comment lines out, so a contract cannot be satisfied by a comment.
    private func code(_ path: String) throws -> String {
        try source(path).split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: PortSourceScrubTests.repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    private func index(of needle: String, in text: String) throws -> String.Index {
        try #require(text.range(of: needle), "missing: \(needle)").lowerBound
    }

    @Test func debounceAndQuitProtectionPassEverythingThroughBeforeTouchingAKey() throws {
        for (path, feature) in [("Sources/PortKit/Services/KeyboardDebounce/KeyboardDebounceService.swift", "keyboardDebounce"),
                                ("Sources/PortKit/Services/QuitProtection/QuitProtectionService.swift", "quitWindowProtection")] {
            let text = try code(path)
            let guardCall = try index(of: "KeyboardTapSafety.shouldPassThrough(.\(feature))", in: text)
            #expect(guardCall > (try index(of: "tapDisabledByTimeout", in: text)), "\(path): after the disabled-tap branch")
            #expect(guardCall < (try index(of: ".keyboardEventKeycode", in: text)) || path.contains("QuitProtection"),
                    "\(path): before the key is read")
        }
        let quit = try code("Sources/PortKit/Services/QuitProtection/QuitProtectionService.swift")
        let handle = try #require(quit.range(of: "private func handle(type: CGEventType"))
        let afterGuard = quit[try index(of: "KeyboardTapSafety.shouldPassThrough", in: quit)...]
        #expect(afterGuard.prefix(400).contains("cancelPending()") && afterGuard.prefix(400).contains("swallowShortcut = nil"),
                "a press held by the tap is dropped, never left half-swallowed")
        #expect(handle.lowerBound < (try index(of: "KeyboardTapSafety.shouldPassThrough", in: quit)))
    }

    @Test func textSnippetsNeverTouchesASecureFieldNorAStoppedFeature() throws {
        let text = try code("Sources/PortKit/Services/Snippets/TextSnippetService.swift")
        let handle = try index(of: "private func handle(type: CGEventType", in: text)
        let available = try index(of: "guard AppFeature.textSnippets.isAvailable else", in: text)
        let secure = try index(of: "guard !IsSecureEventInputEnabled() else", in: text)
        let expand = try index(of: "return expand(", in: text)
        #expect(handle < available && available < secure && secure < expand,
                "stopped and secure input both pass through before any expansion")
        let library = try code("Sources/PortKit/Services/Snippets/SnippetLibraryService.swift")
        #expect(library.contains("guard !IsSecureEventInputEnabled() else"), "the library never types into a secure field")
    }

    @Test func everyKeyboardTapReArmsAfterATimeoutAndPassesTheEventThrough() throws {
        let files = ["KeyboardDebounce/KeyboardDebounceService", "QuitProtection/QuitProtectionService",
                     "Snippets/TextSnippetService", "SuperKey/SuperKeyService"]
        for file in files {
            let text = try code("Sources/PortKit/Services/\(file).swift")
            let start = try index(of: "tapDisabledByTimeout", in: text)
            let clause = String(text[start...].prefix(1800))
            #expect(clause.contains("CGEvent.tapEnable(") && clause.contains("enable: true)"), "\(file) re-enables the tap")
            #expect(clause.contains("return Unmanaged.passUnretained(event)"), "\(file) lets the event through")
            #expect(clause.contains("SessionActivity.shared.isActive") || clause.contains("SessionActivitySupport"),
                    "\(file) never re-arms into a switched-away session")
        }
    }

    @Test func theStopsDisableAndInvalidateTheirTaps() throws {
        for file in ["KeyboardDebounce/KeyboardDebounceService", "QuitProtection/QuitProtectionService",
                     "Snippets/TextSnippetService", "SuperKey/SuperKeyService"] {
            let text = try code("Sources/PortKit/Services/\(file).swift")
            #expect(text.contains("CGEvent.tapEnable(tap: tap, enable: false)"), "\(file) switches its tap off on stop")
        }
    }

    // MARK: Snippets and the pasteboard

    @Test func theSnippetPasteSnapshotsAndRestoresTheUsersPasteboard() throws {
        let paste = try code("Sources/PortKit/Services/TransientPaste.swift")
        #expect(paste.contains("snapshot(of: pasteboard)") && paste.contains("scheduleRestore(snapshot:"))
        #expect(paste.contains("guard pasteboard.changeCount == changeCount else { return }"),
                "the restore never overwrites something the user copied meanwhile")
        let snippets = try code("Sources/PortKit/Services/Snippets/TextSnippetService.swift")
        #expect(snippets.contains("TransientPaste.shared.paste("), "a multi-line snippet goes through the restoring paste")
    }
}
