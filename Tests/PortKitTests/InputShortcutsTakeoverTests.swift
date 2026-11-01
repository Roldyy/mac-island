import CoreGraphics
import Foundation
import Testing
@testable import PortKit

/// The WindowServer's symbolic hotkey table as a dictionary: what `SystemShortcutTakeover` would flip for real.
private final class FakeHotKeyTable: @unchecked Sendable {
    private let lock = NSLock()
    private var enabledIDs: [Int32: Bool]
    private(set) var writes: [(Int32, Bool)] = []
    var refuseEnable = false
    /// What the persisted marker held at the moment of each write (the write-ahead check).
    private(set) var markerAtWrite: [Set<Int>] = []
    let defaults: UserDefaults
    let entries: [LiveSystemShortcut]

    init(entries: [LiveSystemShortcut], defaults: UserDefaults) {
        self.entries = entries
        self.defaults = defaults
        enabledIDs = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.enabled) })
    }

    func isEnabled(_ id: Int32) -> Bool { lock.withLock { enabledIDs[id] ?? false } }

    var store: SystemShortcutTakeover.Store {
        SystemShortcutTakeover.Store(
            setEnabled: { [self] id, on in
                lock.withLock {
                    if on && refuseEnable { return .failure }
                    writes.append((id, on))
                    markerAtWrite.append(Set((defaults.array(forKey: DefaultsKey.systemShortcutsSuppressed) as? [Int]) ?? []))
                    enabledIDs[id] = on
                    return .success
                }
            },
            isEnabled: { [self] id in isEnabled(id) },
            liveEntries: { [self] in
                lock.withLock { entries.map { LiveSystemShortcut(id: $0.id, shortcut: $0.shortcut, enabled: enabledIDs[$0.id] ?? false) } }
            })
    }
}

@Suite(.serialized) struct InputShortcutsTakeoverTests {
    private static let shortcut = GlobalShortcut(keyCode: 20, modifiers: [.control, .command])  // ⌃⌘3
    private static let roleKey = "someFeatureShortcut"

    private func table(_ defaults: UserDefaults) -> FakeHotKeyTable {
        FakeHotKeyTable(entries: [LiveSystemShortcut(id: 7, shortcut: Self.shortcut, enabled: true)], defaults: defaults)
    }

    @Test func nothingIsTakenOverUntilThePersonAcceptsTheOffer() {
        PortHostFixture.isolated { defaults in
            let t = table(defaults)
            SystemShortcutTakeover.resetForTests(store: t.store)
            SystemShortcutTakeover.claim(Self.roleKey, shortcut: Self.shortcut)
            #expect(t.writes.isEmpty && SystemShortcutTakeover.heldIDs.isEmpty, "off by default")

            // A consent migrated from Vorssaint is not consent here.
            defaults.set([Self.roleKey], forKey: "systemShortcutTakeOverKeys")
            SystemShortcutTakeover.resetForTests(store: t.store)
            SystemShortcutTakeover.claim(Self.roleKey, shortcut: Self.shortcut)
            #expect(t.writes.isEmpty && !SystemShortcutTakeover.isTakenOver(Self.roleKey))
        }
    }

    @Test func acceptingTakesTheKeyWithTheMarkerWrittenFirstAndReleasingGivesItBack() {
        PortHostFixture.isolated { defaults in
            let t = table(defaults)
            SystemShortcutTakeover.resetForTests(store: t.store)
            SystemShortcutTakeover.claim(Self.roleKey, shortcut: Self.shortcut)
            SystemShortcutTakeover.setTakeOver(Self.roleKey, true)
            #expect(t.writes.map(\.0) == [7] && t.writes.map(\.1) == [false])
            #expect(t.markerAtWrite == [[7]], "the crash marker is on disk before macOS is changed")
            #expect(SystemShortcutTakeover.heldIDs == [7])
            #expect(defaults.stringArray(forKey: SystemShortcutTakeover.consentKey) == [Self.roleKey])

            SystemShortcutTakeover.release(Self.roleKey)
            #expect(t.isEnabled(7) && SystemShortcutTakeover.heldIDs.isEmpty)
            #expect(defaults.object(forKey: DefaultsKey.systemShortcutsSuppressed) == nil, "marker cleared once restored")
        }
    }

    @Test func quitGivesEveryKeyBack() {
        PortHostFixture.isolated { defaults in
            let t = table(defaults)
            SystemShortcutTakeover.resetForTests(store: t.store)
            SystemShortcutTakeover.setTakeOver(Self.roleKey, true)
            SystemShortcutTakeover.claim(Self.roleKey, shortcut: Self.shortcut)
            #expect(!t.isEnabled(7))
            SystemShortcutTakeover.restoreAll()
            #expect(t.isEnabled(7) && SystemShortcutTakeover.heldIDs.isEmpty)
        }
    }

    @Test func aCrashIsRepairedAtTheNextLaunchFromTheMarker() {
        PortHostFixture.isolated { defaults in
            // The previous run died with key 7 switched off: the marker survived, the table did too.
            let t = table(defaults)
            _ = t.store.setEnabled?(7, false)
            defaults.set([7], forKey: DefaultsKey.systemShortcutsSuppressed)
            #expect(PortBridge.RecoveryPlan(defaults: defaults).systemShortcuts, "the launch step enters recovery")

            SystemShortcutTakeover.resetForTests(store: t.store)
            SystemShortcutTakeover.recoverIfNeeded(keeping: [])
            #expect(t.isEnabled(7))
            #expect(SystemShortcutTakeover.heldIDs.isEmpty)
            #expect(defaults.object(forKey: DefaultsKey.systemShortcutsSuppressed) == nil)
        }
    }

    @Test func aRestoreTheSystemRefusesKeepsTheMarkerForTheNextTry() {
        PortHostFixture.isolated { defaults in
            let t = table(defaults)
            SystemShortcutTakeover.resetForTests(store: t.store)
            SystemShortcutTakeover.setTakeOver(Self.roleKey, true)
            SystemShortcutTakeover.claim(Self.roleKey, shortcut: Self.shortcut)
            t.refuseEnable = true
            SystemShortcutTakeover.restoreAll()
            #expect(SystemShortcutTakeover.heldIDs == [7])
            #expect(defaults.array(forKey: DefaultsKey.systemShortcutsSuppressed) as? [Int] == [7])
            t.refuseEnable = false
            SystemShortcutTakeover.recoverIfNeeded(keeping: [])
            #expect(t.isEnabled(7) && SystemShortcutTakeover.heldIDs.isEmpty)
        }
    }

    @Test func aMacOSCombinationIsOfferedNeverSilentlyTaken() {
        let decision = SystemShortcutTakeoverSupport.recorderDecision(
            shortcut: Self.shortcut, conflictsWithMacOS: true, takenOver: false, current: nil)
        #expect(decision == .offer)
        #expect(SystemShortcutTakeoverSupport.recorderDecision(
            shortcut: Self.shortcut, conflictsWithMacOS: false, takenOver: false, current: nil)
            == .save(clearTakeOver: true))
    }
}
