// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W2A (display). The lane owns this file.

import CoreGraphics
import Foundation

/// The note that a software (gamma) dim is on a screen, kept on disk so a run that dies dimmed is cleaned up at
/// the next launch.
///
/// macOS itself puts a process's gamma curves back when the process exits, so this is the second net, for the
/// cases where that does not happen (a hung process killed late, a crash in the window server's bookkeeping, a
/// dim another run left behind). It is deliberately narrow: `CGDisplayRestoreColorSyncSettings` resets EVERY
/// display's curve to the ColorSync profile, which would undo a colour tint another tool applied, so it is only
/// called when this note says Mac Island had a dim up.
///
/// The ported brightness service calls `note(dimmed:)` from its work queue around every curve it writes; the
/// write itself happens on the main thread (a `UserDefaults` write posts a notification whose main-queue
/// observers must not be waited on from the service's lock or queue, the upstream issue #647 lesson).
enum DisplayGammaJournal {
    /// Our own key: not a Vorssaint key, so the migrator and the runtime-key purge never see it.
    static let key = "macIslandDisplayGammaDimActive"

    private static let memory = NoteMemory()

    /// Records that a dim is (true) or is no longer (false) on a screen. Cheap and thread-safe: repeating the
    /// same answer writes nothing.
    static func note(dimmed: Bool) {
        guard memory.changed(to: dimmed) else { return }
        let defaults = PortHost.defaults
        if Thread.isMainThread {
            write(dimmed: dimmed, defaults: defaults)
        } else {
            DispatchQueue.main.async { write(dimmed: dimmed, defaults: defaults) }
        }
    }

    /// The synchronous write. Tests and the quit hook call it directly.
    static func write(dimmed: Bool, defaults: UserDefaults) {
        if dimmed { defaults.set(true, forKey: key) } else { defaults.removeObject(forKey: key) }
        memory.set(dimmed)
    }

    /// Whether the previous run left a dim up.
    static func isMarked(in defaults: UserDefaults) -> Bool { defaults.bool(forKey: key) }

    /// Launch recovery: when the note is set, puts every display back to its ColorSync curve and clears the note.
    /// Returns whether it acted. Never prompts, never starts the brightness service, touches no private API.
    @discardableResult
    static func recoverAtLaunch(defaults: UserDefaults,
                                restore: () -> Void = { CGDisplayRestoreColorSyncSettings() }) -> Bool {
        guard isMarked(in: defaults) else { return false }
        restore()
        write(dimmed: false, defaults: defaults)
        return true
    }

    /// Forgets what was last noted (tests).
    static func resetMemory() { memory.reset() }

    /// The last answer given, so a repeated one is not written again. nil until the first answer.
    private final class NoteMemory: @unchecked Sendable {
        private let lock = NSLock()
        private var last: Bool?

        func changed(to value: Bool) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard last != value else { return false }
            last = value
            return true
        }

        func set(_ value: Bool) { lock.lock(); last = value; lock.unlock() }
        func reset() { lock.lock(); last = nil; lock.unlock() }
    }
}
