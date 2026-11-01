// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import AppKit
import Foundation

/// Switches WindowServer symbolic hotkeys off for as long as a Vorssaint
/// feature wants a key macOS would otherwise answer, and gives them back on
/// every exit path. Only ids that are enabled right now are ever touched, and
/// the marker is written before each change so a crash can be repaired at the
/// next launch. Callers decide which ids; this decides how.
enum SystemShortcutTakeover {
    /// The three things this service asks of the WindowServer, so a test can stand a fake table in their place.
    /// `live` is the private SkyLight calls; each is nil on a macOS that dropped them (nothing is then touched).
    struct Store {
        var setEnabled: ((Int32, Bool) -> CGError)?
        var isEnabled: ((Int32) -> Bool)?
        var liveEntries: () -> [LiveSystemShortcut]?

        static let live = Store(setEnabled: SymbolicHotKeys.setEnabled,
                                isEnabled: SymbolicHotKeys.isEnabled,
                                liveEntries: { SymbolicHotKeys.liveEntries() })
    }

    /// Mac Island's own consent list. The Vorssaint key of the same purpose (`systemShortcutTakeOverKeys`) is
    /// migrated like any other preference, but a consent given in another app is not consent here: nothing is
    /// taken over from macOS until the person accepts the offer in THIS app, which writes this key.
    static let consentKey = "systemShortcutTakeOverKeys.macisland"

    private static let lock = NSLock()
    private static var store = Store.live
    private static var suppressed: Set<Int32> = SystemShortcutTakeoverSupport.migratedMarker(
        old: PortHost.defaults.array(forKey: DefaultsKey.switcherNativeHotkeysSuppressed) as? [Int],
        new: PortHost.defaults.array(forKey: DefaultsKey.systemShortcutsSuppressed) as? [Int])
    static let switcherSource = "switcher"
    private static var wanted: [String: Set<Int32>] = [:]
    private static var claims: [String: GlobalShortcut] = [:]
    private static var takeOverKeys: Set<String> = Set(
        PortHost.defaults.stringArray(forKey: consentKey) ?? [])
    private static var wakeObserver: NSObjectProtocol?

    /// Tests only: a fake table and a clean slate, state read afresh from `PortHost.defaults`.
    static func resetForTests(store newStore: Store) {
        lock.lock()
        defer { lock.unlock() }
        store = newStore
        suppressed = SystemShortcutTakeoverSupport.migratedMarker(
            old: PortHost.defaults.array(forKey: DefaultsKey.switcherNativeHotkeysSuppressed) as? [Int],
            new: PortHost.defaults.array(forKey: DefaultsKey.systemShortcutsSuppressed) as? [Int])
        wanted = [:]
        claims = [:]
        takeOverKeys = Set(PortHost.defaults.stringArray(forKey: consentKey) ?? [])
    }

    /// Tests only: the ids this service holds off right now.
    static var heldIDs: Set<Int32> {
        lock.lock()
        defer { lock.unlock() }
        return suppressed
    }

    /// Raw-id callers (the switcher) say what they want under their own name.
    static func setWanted(_ ids: Set<Int32>, for source: String) {
        lock.lock()
        defer { lock.unlock() }
        if ids.isEmpty { wanted.removeValue(forKey: source) } else { wanted[source] = ids }
        applyLocked(desired: SystemShortcutTakeoverSupport.union(of: wanted))
    }

    /// A feature whose hotkey just registered. Only shortcuts the user chose to
    /// take over resolve to any ids; everything else is a no-op that costs one
    /// dictionary write.
    static func claim(_ storageKey: String, shortcut: GlobalShortcut) {
        lock.lock()
        claims[storageKey] = shortcut
        lock.unlock()
        refresh(storageKey)
    }

    static func release(_ storageKey: String) {
        lock.lock()
        claims.removeValue(forKey: storageKey)
        lock.unlock()
        setWanted([], for: storageKey)
    }

    /// The recorder's choice, kept as a preference so it survives a relaunch.
    static func setTakeOver(_ storageKey: String, _ on: Bool) {
        lock.lock()
        if on { takeOverKeys.insert(storageKey) } else { takeOverKeys.remove(storageKey) }
        PortHost.defaults.set(takeOverKeys.sorted(), forKey: consentKey)
        lock.unlock()
        refresh(storageKey)
    }

    static func isTakenOver(_ storageKey: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return takeOverKeys.contains(storageKey)
    }

    /// What a shortcut field must ask before it decides. A key this service is
    /// holding is missing from the live table's answer, so asking the table
    /// alone tells the row that the combination it took over is free — and the
    /// row saves it as an ordinary key, dropping the opt-in that was keeping it.
    static func conflictsWithMacOS(_ shortcut: GlobalShortcut, for role: GlobalShortcutRole? = nil) -> Bool {
        lock.lock()
        let held = suppressed
        let live = store.liveEntries
        lock.unlock()
        return SystemShortcutTakeoverSupport.conflictsWithMacOS(
            shortcut,
            liveEntries: live(),
            symbolicHotKeys: GlobalShortcut.systemSymbolicHotKeys,
            held: held,
            role: role)
    }

    /// The live table can change under us (System Settings, another app, wake).
    /// Re-resolve every claim; `apply` only writes what actually differs.
    static func reconcile() {
        let keys: [String]
        lock.lock()
        keys = Array(claims.keys)
        lock.unlock()
        for key in keys { refresh(key) }
    }

    private static func refresh(_ storageKey: String) {
        lock.lock()
        let shortcut = takeOverKeys.contains(storageKey) ? claims[storageKey] : nil
        let live = store.liveEntries
        lock.unlock()
        guard let shortcut else {
            setWanted([], for: storageKey)
            return
        }
        // A nil table means the private calls are missing on this macOS, so
        // nothing could have been taken over and nothing needs handing back.
        guard let entries = live() else { return }
        setWanted(SystemShortcutTakeoverSupport.ids(matching: shortcut, in: entries), for: storageKey)
    }

    /// Quit: every key a feature took over goes back, whichever feature held
    /// it. Not every claimant suspends in `applicationWillTerminate`, and the
    /// ones that do should not each have to remember this.
    static func restoreAll() {
        lock.lock()
        defer { lock.unlock() }
        wanted.removeAll()
        claims.removeAll()
        applyLocked(desired: [])
    }

    /// The transition itself. Callers hold `lock`, so the decision about what
    /// every source wants and the writes that follow are one critical section.
    private static func applyLocked(desired: Set<Int32>) {
        guard let setEnabled = store.setEnabled,
              let isEnabled = store.isEnabled else { return }
        let candidates = desired.union(suppressed)
        let currentlyEnabled = candidates.filter { isEnabled($0) }
        let transition = SystemShortcutTakeoverSupport.transition(
            from: suppressed, to: desired, currentlyEnabled: currentlyEnabled)
        suppressed = SystemShortcutTakeoverSupport.apply(
            transition, owned: suppressed,
            setEnabled: { setEnabled($0, $1) == .success },
            persist: persist)
        observeWake(!suppressed.isEmpty)
    }

    /// Launch only repairs previous ownership. Keep ids a feature will claim
    /// again without toggling them; new suppression waits for its live handler.
    /// The old switcher marker, already absorbed into `suppressed`, is written to
    /// the shared key before it is removed, so a restore that fails here still
    /// has a marker to retry from.
    static func recoverIfNeeded(keeping desired: Set<Int32>) {
        lock.lock()
        defer { lock.unlock() }
        persist(suppressed)
        PortHost.defaults.removeObject(forKey: DefaultsKey.switcherNativeHotkeysSuppressed)
        guard let setEnabled = store.setEnabled else { return }
        // A feature that claimed before recovery ran (keep-awake registers
        // first) is a source too; keeping only the switcher's ids would give
        // its key back and leave it off.
        let keep = desired.union(SystemShortcutTakeoverSupport.union(of: wanted))
        suppressed = SystemShortcutTakeoverSupport.apply(
            SystemShortcutTakeoverSupport.recoveryTransition(from: suppressed, keeping: keep),
            owned: suppressed,
            setEnabled: { setEnabled($0, $1) == .success },
            persist: persist)
        observeWake(!suppressed.isEmpty)
        // What stayed off for the switcher is held on its behalf until its tap
        // comes up and says so itself. Recorded as its source, or the first
        // claim of the launch resolves what every source wants without those
        // ids and hands them straight back — the flip the keeping exists to
        // avoid. Only ids the marker already owned and that are still off are
        // recorded, so this still takes nothing new — an owned id macOS has
        // since re-enabled is left to the tap; if the tap never starts,
        // `syncWithPreferences` clears the entry and the keys go back as before.
        let isEnabled = store.isEnabled
        let held = desired.intersection(suppressed).filter { isEnabled?($0) != true }
        if !held.isEmpty { wanted[switcherSource] = held }
    }

    /// Wake can leave the live table changed under a claim that is still ours,
    /// so a held key is re-resolved after the switcher's own three seconds, which
    /// keep the two reconciles from racing the WindowServer right after wake.
    /// The observer exists only while some feature holds a key and goes away
    /// when the last one is given back, as the switcher does with its own; a Mac
    /// where nothing was ever taken over never installs it. Callers hold `lock`;
    /// the notification arrives later on the main queue and takes it afresh.
    private static func observeWake(_ holding: Bool) {
        if holding, wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { reconcile() }
                }
        } else if !holding, let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }
    }

    private static func persist(_ ids: Set<Int32>) {
        if ids.isEmpty {
            PortHost.defaults.removeObject(forKey: DefaultsKey.systemShortcutsSuppressed)
        } else {
            PortHost.defaults.set(ids.map(Int.init).sorted(), forKey: DefaultsKey.systemShortcutsSuppressed)
        }
    }
}
