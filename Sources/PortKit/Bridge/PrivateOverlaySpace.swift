// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// New file of lane W8D (lock-screen island). The ONLY place of the lane that touches a private WindowServer symbol
// (`CGSSpace*`, resolved with `dlsym`); listed in scripts/port/private-api-allowlist.txt.

import AppKit
import Darwin
import Foundation

// MARK: - The seam

/// One live Space of the island's own, as the ported `NotchOverlaySpace` sees it.
protocol OverlaySpaceBackend: AnyObject {
    func add(windowNumber: Int)
    func close()
}

enum OverlaySpaceUnavailable: Equatable {
    /// These symbols did not resolve on this macOS.
    case symbolsMissing([String])
    /// The switch below was set (by the person, or by the app after a failure).
    case killSwitch
    /// The previous run died while a lock-screen Space was armed (see `OverlaySpaceGuard.recoverAtLaunch`).
    case crashed
}

enum OverlaySpaceCapability: Equatable {
    case available
    case unavailable(OverlaySpaceUnavailable)
}

protocol OverlaySpaceProviding {
    /// What a call to `makeSpace(absoluteLevel:)` could do right now, without making a Space or writing anything.
    func capability(needsLevel: Bool) -> OverlaySpaceCapability
    /// Nil whenever the capability is not `available`: an unavailable lock-screen island, never a crash.
    func makeSpace(absoluteLevel: Int32?) -> OverlaySpaceBackend?
}

/// The one provider the ported code asks. Tests swap it for a fake; the app never changes it.
enum PrivateOverlaySpace {
    nonisolated(unsafe) static var provider: OverlaySpaceProviding = SkyLightOverlaySpaceProvider.live()
}

// MARK: - Capability probe

/// The symbols the lock-screen Space needs, and which of them a resolver cannot find. Pure: a test passes its own resolver.
enum OverlaySpaceSymbols {
    static let base = ["CGSMainConnectionID", "CGSSpaceCreate", "CGSShowSpaces", "CGSHideSpaces",
                       "CGSAddWindowsToSpaces", "CGSRemoveWindowsFromSpaces", "CGSSpaceDestroy"]
    static let level = "CGSSpaceSetAbsoluteLevel"

    static func missing(needsLevel: Bool, resolves: (String) -> Bool) -> [String] {
        (base + (needsLevel ? [level] : [])).filter { !resolves($0) }
    }

    static let liveResolver: (String) -> Bool = { name in
        dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, name) != nil
    }
}

// MARK: - Journal and kill switch

struct OverlaySpaceJournalEntry: Codable, Equatable {
    var level: Int32
    /// Known once `CGSSpaceCreate` answered; nil while the call itself is in flight.
    var space: UInt64?
    var startedAt: Date
}

protocol OverlaySpaceJournaling: AnyObject {
    /// Durable BEFORE the first private call. False when it could not be written: then no private call is made.
    func begin(level: Int32) -> Bool
    func record(space: UInt64)
    func clear()
    func read() -> OverlaySpaceJournalEntry?
}

/// The journal as an owner-only file in the app's private container.
final class FileOverlaySpaceJournal: OverlaySpaceJournaling {
    private let url: URL?
    private let now: () -> Date

    init(url: URL? = FileOverlaySpaceJournal.defaultURL, now: @escaping () -> Date = Date.init) {
        self.url = url
        self.now = now
    }

    static var defaultURL: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent("Journal", isDirectory: true)
            .appendingPathComponent("overlay-space.json")
    }

    func begin(level: Int32) -> Bool {
        write(OverlaySpaceJournalEntry(level: level, space: nil, startedAt: now()))
    }

    func record(space: UInt64) {
        guard var entry = read() else { return }
        entry.space = space
        _ = write(entry)
    }

    func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func read() -> OverlaySpaceJournalEntry? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(OverlaySpaceJournalEntry.self, from: data)
    }

    private func write(_ entry: OverlaySpaceJournalEntry) -> Bool {
        guard let url, let data = try? JSONEncoder().encode(entry) else { return false }
        _ = PrivateFileStore.createDirectory(at: url.deletingLastPathComponent())
        return PrivateFileStore.write(data, to: url) && (try? Data(contentsOf: url)) == data
    }
}

/// The switch that keeps the lock-screen island down: set by the person (a Settings switch), or by the app itself when the
/// previous run died with a Space armed. Cleared only by the person ("Réessayer").
struct OverlaySpaceGuard {
    static let killKey = "macIslandOverlaySpaceKill"
    static let crashedKey = "macIslandOverlaySpaceCrashed"

    let defaults: UserDefaults

    var blocked: OverlaySpaceUnavailable? {
        if defaults.bool(forKey: Self.crashedKey) { return .crashed }
        if defaults.bool(forKey: Self.killKey) { return .killSwitch }
        return nil
    }

    /// A journal still on disk at launch means a run died between "about to create the lock-screen Space" and "destroyed
    /// it". WindowServer reclaims a dead connection's Spaces by itself, so nothing is destroyed here (a stored id could
    /// by now belong to somebody else); the island simply stays off until the person asks again. Returns true when it
    /// found one. Entered at every launch, writes nothing when there is no journal.
    @discardableResult
    static func recoverAtLaunch(journal: OverlaySpaceJournaling, defaults: UserDefaults) -> Bool {
        guard journal.read() != nil else { return false }
        defaults.set(true, forKey: crashedKey)
        journal.clear()
        return true
    }

    /// "Réessayer": the person lifts both the crash lock and the kill switch.
    static func reset(defaults: UserDefaults) {
        defaults.removeObject(forKey: crashedKey)
        defaults.removeObject(forKey: killKey)
    }
}

// MARK: - The calls

/// The seven private calls, so the order of events around them is testable with a fake.
protocol OverlaySpaceCalls: AnyObject {
    func create() -> UInt64
    func setLevel(space: UInt64, level: Int32) -> Bool
    func show(space: UInt64)
    func hide(space: UInt64)
    func add(windows: [Int], space: UInt64)
    func remove(windows: [Int], space: UInt64)
    func destroy(space: UInt64)
}

/// `dlsym` against the running process, as upstream did. Nil when any base symbol is missing.
final class DlsymOverlaySpaceCalls: OverlaySpaceCalls {
    private typealias ConnectionID = UInt32
    private typealias CreateFunction = @convention(c) (ConnectionID, Int32, CFDictionary?) -> UInt64
    private typealias SpacesFunction = @convention(c) (ConnectionID, CFArray) -> Int32
    private typealias WindowsFunction = @convention(c) (ConnectionID, CFArray, CFArray) -> Void
    private typealias DestroyFunction = @convention(c) (ConnectionID, UInt64) -> Void
    private typealias LevelFunction = @convention(c) (ConnectionID, UInt64, Int32) -> Int32

    private let connection: ConnectionID
    private let createFunction: CreateFunction
    private let showFunction: SpacesFunction
    private let hideFunction: SpacesFunction
    private let addFunction: WindowsFunction
    private let removeFunction: WindowsFunction
    private let destroyFunction: DestroyFunction
    private let levelFunction: LevelFunction?

    init?() {
        func symbol(_ name: String) -> UnsafeMutableRawPointer? {
            dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, name)
        }
        guard let main = symbol("CGSMainConnectionID"), let create = symbol("CGSSpaceCreate"),
              let show = symbol("CGSShowSpaces"), let hide = symbol("CGSHideSpaces"),
              let add = symbol("CGSAddWindowsToSpaces"), let remove = symbol("CGSRemoveWindowsFromSpaces"),
              let destroy = symbol("CGSSpaceDestroy") else { return nil }
        let connection = unsafeBitCast(main, to: (@convention(c) () -> ConnectionID).self)()
        guard connection != 0 else { return nil }
        self.connection = connection
        createFunction = unsafeBitCast(create, to: CreateFunction.self)
        showFunction = unsafeBitCast(show, to: SpacesFunction.self)
        hideFunction = unsafeBitCast(hide, to: SpacesFunction.self)
        addFunction = unsafeBitCast(add, to: WindowsFunction.self)
        removeFunction = unsafeBitCast(remove, to: WindowsFunction.self)
        destroyFunction = unsafeBitCast(destroy, to: DestroyFunction.self)
        levelFunction = symbol(OverlaySpaceSymbols.level).map { unsafeBitCast($0, to: LevelFunction.self) }
    }

    func create() -> UInt64 {
        // Any flag but 1 makes Finder draw the desktop icons in this Space.
        createFunction(connection, 1, nil)
    }

    func setLevel(space: UInt64, level: Int32) -> Bool {
        guard let levelFunction else { return false }
        return levelFunction(connection, space, level) == 0
    }

    func show(space: UInt64) { _ = showFunction(connection, [NSNumber(value: space)] as CFArray) }
    func hide(space: UInt64) { _ = hideFunction(connection, [NSNumber(value: space)] as CFArray) }

    func add(windows: [Int], space: UInt64) {
        addFunction(connection, windows.map { NSNumber(value: $0) } as CFArray, [NSNumber(value: space)] as CFArray)
    }

    func remove(windows: [Int], space: UInt64) {
        removeFunction(connection, windows.map { NSNumber(value: $0) } as CFArray, [NSNumber(value: space)] as CFArray)
    }

    func destroy(space: UInt64) { destroyFunction(connection, space) }
}

// MARK: - The provider

/// Makes the island's Space, the safe way round. In this order, every time:
/// 1. the capability: kill switch, crash lock, symbols (nothing is written or called while it says no);
/// 2. for a lock-screen Space (an absolute level), the journal is written and read back BEFORE the first private call,
///    and no journal means no call;
/// 3. the Space is created, given its level and shown; a failure destroys what was made and clears the journal;
/// 4. closing removes the windows first, hides, destroys, and only then clears the journal.
/// A crash anywhere between 2 and 4 leaves the journal, and the next launch keeps the island down until the person
/// asks again (`OverlaySpaceGuard.recoverAtLaunch`).
final class SkyLightOverlaySpaceProvider: OverlaySpaceProviding {
    private let calls: OverlaySpaceCalls?
    private let resolves: (String) -> Bool
    private let journal: OverlaySpaceJournaling
    private let defaults: () -> UserDefaults

    init(calls: OverlaySpaceCalls?, resolves: @escaping (String) -> Bool = OverlaySpaceSymbols.liveResolver,
         journal: OverlaySpaceJournaling = FileOverlaySpaceJournal(),
         defaults: @escaping () -> UserDefaults = { PortHost.defaults }) {
        self.calls = calls
        self.resolves = resolves
        self.journal = journal
        self.defaults = defaults
    }

    static func live() -> SkyLightOverlaySpaceProvider { SkyLightOverlaySpaceProvider(calls: DlsymOverlaySpaceCalls()) }

    func capability(needsLevel: Bool) -> OverlaySpaceCapability {
        if let blocked = OverlaySpaceGuard(defaults: defaults()).blocked { return .unavailable(blocked) }
        let missing = OverlaySpaceSymbols.missing(needsLevel: needsLevel, resolves: resolves)
        if !missing.isEmpty || calls == nil { return .unavailable(.symbolsMissing(missing)) }
        return .available
    }

    func makeSpace(absoluteLevel: Int32?) -> OverlaySpaceBackend? {
        guard capability(needsLevel: absoluteLevel != nil) == .available, let calls else { return nil }
        let journaled = absoluteLevel != nil
        if let absoluteLevel {
            // Journal first: durable and read back before `CGSSpaceCreate` is called.
            guard journal.begin(level: absoluteLevel) else { return nil }
        }
        let space = calls.create()
        guard space != 0 else {
            if journaled { journal.clear() }
            return nil
        }
        if journaled { journal.record(space: space) }
        if let absoluteLevel, !calls.setLevel(space: space, level: absoluteLevel) {
            calls.destroy(space: space)
            if journaled { journal.clear() }
            return nil
        }
        calls.show(space: space)
        return OverlaySpaceHandle(calls: calls, space: space, journal: journaled ? journal : nil)
    }
}

final class OverlaySpaceHandle: OverlaySpaceBackend {
    private let calls: OverlaySpaceCalls
    private let space: UInt64
    private let journal: OverlaySpaceJournaling?
    private var windows = Set<Int>()
    private var closed = false

    init(calls: OverlaySpaceCalls, space: UInt64, journal: OverlaySpaceJournaling?) {
        self.calls = calls
        self.space = space
        self.journal = journal
    }

    /// Joins a window before it is first ordered in: one already on screen would stay on its desktop as well.
    func add(windowNumber: Int) {
        guard !closed, windowNumber > 0, windows.insert(windowNumber).inserted else { return }
        calls.add(windows: [windowNumber], space: space)
    }

    /// Windows leave before the Space goes: a window whose only Space is destroyed would belong to none.
    func close() {
        guard !closed else { return }
        closed = true
        if !windows.isEmpty {
            calls.remove(windows: Array(windows), space: space)
            windows.removeAll()
        }
        calls.hide(space: space)
        calls.destroy(space: space)
        journal?.clear()
    }
}
