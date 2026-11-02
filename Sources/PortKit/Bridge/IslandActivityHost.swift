// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// New file of the island activities lanes W8C and W8D (group 2): the hosting flag the patched notch services read,
// and the board that turns what they report into `IslandActivity` values, with the "Combiner" choice.

import Foundation
import IslandKit
import SwiftUI

// MARK: - Hosting flag

/// Says that Mac Island's OWN island hosts the ported activities (downloads, watch, mascot, gestures, lock screen).
///
/// Upstream asked `NotchSupport.isEnabled()` ("is Vorssaint's island running?") before each of these features did
/// anything. That gate stays false here (one island, `PortHost.vorssaintIslandEnabled`), and flipping it would bring up
/// Vorssaint's window. Patch 1650 therefore makes the six support checks of THIS lane (`NotchSupport.islandIsEnabled`)
/// accept this flag as well. Nothing else reads it: the shelf's top-centre rule and the other `NotchSupport.isEnabled`
/// callers keep upstream's meaning.
///
/// A feature acquires it in its registry start and releases it in its stop, so the flag is on exactly while one of
/// them is allowed to run (off, kill switch, safe mode and quarantine all end in a stop).
public final class IslandActivityHost: @unchecked Sendable {
    public static let shared = IslandActivityHost()

    private let lock = NSLock()
    private var owners: Set<String> = []

    public init() {}

    /// Safe from any thread: the download and watch services ask from their own queues.
    public var isHosting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !owners.isEmpty
    }

    public func acquire(_ owner: String) {
        lock.lock()
        let changed = owners.insert(owner).inserted
        lock.unlock()
        if changed { IslandHostTicker.notify() }
    }

    public func release(_ owner: String) {
        lock.lock()
        let changed = owners.remove(owner) != nil
        lock.unlock()
        if changed { IslandHostTicker.notify() }
    }

    public func holds(_ owner: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return owners.contains(owner)
    }
}

/// What SwiftUI watches instead of the lock-protected flag above: every change of who hosts bumps `tick` on the main
/// actor, and a view that reads `holds` observes this object, so a page appears or empties the moment its feature switch
/// changes (a switch flipped while the page is on screen used to show the old state until something else redrew it).
@MainActor
public final class IslandHostTicker: ObservableObject {
    public static let shared = IslandHostTicker()
    @Published public private(set) var tick = 0

    nonisolated static func notify() {
        Task { @MainActor in shared.tick += 1 }
    }
}

extension NotchSupport {
    /// Upstream's `isEnabled(in:)` OR "Mac Island hosts the activities". Used by the patched checks of lane group 2 only.
    static func islandIsEnabled(in defaults: UserDefaults = PortHost.defaults) -> Bool {
        IslandActivityHost.shared.isHosting || isEnabled(in: defaults)
    }

    /// Upstream's `showsFiles(in:)` (the island is on and shows its Files module) with the same hosting rule.
    static func islandShowsFiles(in defaults: UserDefaults = PortHost.defaults) -> Bool {
        islandIsEnabled(in: defaults) && modules(in: defaults).contains(.files)
    }
}

// MARK: - Posting

/// Where the board sends activities. `ActivityCenter` in the app, a recorder in tests.
@MainActor
public protocol IslandActivityPosting: AnyObject {
    func post(_ activity: IslandActivity, expiresAfter: Duration?)
    func withdraw(id: String)
}

extension ActivityCenter: IslandActivityPosting {}

// MARK: - Combination

/// Two sources sharing the closed island: the primary keeps its reading right of the camera and the companion's mark
/// takes the left (as upstream's `NotchActivityCombination`). Sources are feature ids (`notchDownloads`, `notchWatch`).
public struct IslandCombination: Equatable, Hashable, Sendable {
    public let primary: String
    public let companion: String

    public init(primary: String, companion: String) {
        self.primary = primary
        self.companion = companion
    }

    static let storageKey = "macIslandActivityCombination"

    var stored: String { primary + "+" + companion }

    init?(stored: String?) {
        guard let parts = stored?.split(separator: "+", omittingEmptySubsequences: false), parts.count == 2,
              !parts[0].isEmpty, !parts[1].isEmpty, parts[0] != parts[1] else { return nil }
        self.init(primary: String(parts[0]), companion: String(parts[1]))
    }
}

/// What the board knows about a source, for the menu.
public struct IslandActivitySource: Equatable, Sendable {
    public let id: String
    public let title: String
    public let symbol: String

    public init(id: String, title: String, symbol: String) {
        self.id = id
        self.title = title
        self.symbol = symbol
    }
}

// MARK: - Board

/// Holds the activities of the ported island features and sends the closed island what it should draw.
///
/// Alone, an activity goes to the center unchanged. With a chosen combination whose two sources are both active, the
/// board posts ONE merged activity instead (the companion's mark on the left wing, the primary's reading on the right
/// wing, the better of the two priorities) and withdraws the two it replaces; the moment one of them ends, the other
/// comes back on its own. The choice is a stored string, so a pair that is not active now is simply waiting.
///
/// The board posts nothing until a feature gives it something, so the closed island stays as it was (Claude left,
/// clock centre, battery and cup right) while all these features are off.
@MainActor
public final class IslandActivityBoard {
    public static let shared = IslandActivityBoard()

    static let combinedID = "island.combined"

    private struct Entry {
        var activity: IslandActivity
        var generation: Int
    }

    private let poster: @MainActor () -> IslandActivityPosting
    private let defaults: () -> UserDefaults
    private let sleep: @Sendable (Duration) async throws -> Void
    private var entries: [String: Entry] = [:]
    private var expiries: [String: Task<Void, Never>] = [:]
    private var posted: [String: IslandActivity] = [:]
    private var sources: [String: IslandActivitySource] = [:]
    private var counter = 0

    public init(poster: @escaping @MainActor () -> IslandActivityPosting = { ActivityCenter.shared },
                defaults: @escaping () -> UserDefaults = { PortHost.defaults },
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.poster = poster
        self.defaults = defaults
        self.sleep = sleep
    }

    // MARK: Sources

    public func register(_ source: IslandActivitySource) { sources[source.id] = source }

    // MARK: Posting

    /// Posting an id again replaces it and restarts its expiry.
    public func post(_ activity: IslandActivity, expiresAfter: Duration? = nil) {
        counter += 1
        entries[activity.id] = Entry(activity: activity, generation: counter)
        expiries.removeValue(forKey: activity.id)?.cancel()
        if let expiresAfter {
            let id = activity.id
            let generation = counter
            let sleep = self.sleep
            expiries[id] = Task { [weak self] in
                do { try await sleep(expiresAfter) } catch { return }
                self?.expire(id: id, generation: generation)
            }
        }
        reconcile()
    }

    public func withdraw(id: String) {
        expiries.removeValue(forKey: id)?.cancel()
        guard entries.removeValue(forKey: id) != nil else { return }
        reconcile()
    }

    /// A feature turning off drops everything it posted.
    public func withdrawAll(source: String) {
        let ids = entries.values.filter { $0.activity.source == source }.map(\.activity.id)
        for id in ids {
            expiries.removeValue(forKey: id)?.cancel()
            entries.removeValue(forKey: id)
        }
        if !ids.isEmpty { reconcile() }
    }

    private func expire(id: String, generation: Int) {
        guard entries[id]?.generation == generation else { return }
        expiries.removeValue(forKey: id)
        entries.removeValue(forKey: id)
        reconcile()
    }

    // MARK: Combination

    public var combination: IslandCombination? {
        IslandCombination(stored: defaults().string(forKey: IslandCombination.storageKey))
    }

    /// Chooses a pair, or `nil` to show the sources apart again.
    public func select(_ combination: IslandCombination?) {
        if let combination {
            defaults().set(combination.stored, forKey: IslandCombination.storageKey)
        } else {
            defaults().removeObject(forKey: IslandCombination.storageKey)
        }
        reconcile()
    }

    /// The pairs the menu offers: two different active sources, each as primary with the other as companion, in the
    /// sources' own order. Only sources active NOW are offered, so the menu never promises a strip that cannot draw.
    public var offeredCombinations: [IslandCombination] {
        let active = activeSources
        return active.flatMap { primary in
            active.filter { $0 != primary }.map { IslandCombination(primary: primary, companion: $0) }
        }
    }

    /// Menu title, in the order the island shows them, left to right ("companion + primary").
    public func title(of combination: IslandCombination) -> String {
        (sources[combination.companion]?.title ?? combination.companion) + " + "
            + (sources[combination.primary]?.title ?? combination.primary)
    }

    public func symbol(of source: String) -> String { sources[source]?.symbol ?? "circle" }

    private var activeSources: [String] {
        var seen: [String] = []
        for entry in entries.values.sorted(by: { $0.activity.id < $1.activity.id })
        where !seen.contains(entry.activity.source) && sources[entry.activity.source] != nil {
            seen.append(entry.activity.source)
        }
        return seen
    }

    // MARK: Reconcile

    /// The activities the center should hold now, by id. Pure of the center: tests read it directly.
    func desired() -> [String: IslandActivity] {
        var result = entries.mapValues(\.activity)
        guard let pair = combination,
              let primary = best(of: pair.primary), let companion = best(of: pair.companion) else { return result }
        for id in result.keys where result[id]?.source == pair.primary || result[id]?.source == pair.companion {
            result.removeValue(forKey: id)
        }
        let mark = companion.leading ?? companion.trailing
        result[Self.combinedID] = IslandActivity(
            id: Self.combinedID, source: pair.primary, priority: max(primary.priority, companion.priority),
            leading: mark.map { CompactItem(symbol: $0.symbol, text: nil, status: $0.status, progress: $0.progress) },
            trailing: primary.trailing ?? primary.leading, showsDot: false)
        return result
    }

    private func best(of source: String) -> IslandActivity? {
        entries.values.map(\.activity).filter { $0.source == source }
            .max { a, b in a.priority != b.priority ? a.priority < b.priority : a.id > b.id }
    }

    private func reconcile() {
        let target = desired()
        let center = poster()
        for id in posted.keys where target[id] == nil {
            center.withdraw(id: id)
            posted.removeValue(forKey: id)
        }
        for (id, activity) in target where posted[id] != activity {
            center.post(activity, expiresAfter: nil)
            posted[id] = activity
        }
    }
}

// MARK: - The "Combiner" menu

/// The island's own menu to pair two active sources, in French, on the frosted tokens of `IslandUI`. Empty (no view at
/// all) while fewer than two sources are active, as upstream hides its menu then.
public struct IslandCombineMenu: View {
    private let board: IslandActivityBoard
    @State private var tick = 0

    @MainActor public init(board: IslandActivityBoard? = nil) { self.board = board ?? .shared }

    public var body: some View {
        let pairs = board.offeredCombinations
        let current = board.combination
        if !pairs.isEmpty || current != nil {
            Menu {
                ForEach(pairs, id: \.self) { pair in
                    Button {
                        board.select(pair)
                        tick += 1
                    } label: {
                        Label(board.title(of: pair), systemImage: current == pair ? "checkmark" : board.symbol(of: pair.companion))
                    }
                }
                if current != nil {
                    Divider()
                    Button("Séparer les activités", systemImage: "rectangle.split.2x1") {
                        board.select(nil)
                        tick += 1
                    }
                }
            } label: {
                Label(current.map { board.title(of: $0) } ?? "Combiner",
                      systemImage: current == nil ? "plus" : "checkmark")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Combiner deux activités dans l’île fermée")
            .accessibilityIdentifier("island.activity.combine")
            .id(tick)
        }
    }
}
