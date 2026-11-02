// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management

import Combine
import Foundation
import IslandKit

/// The companion as an indicator of the closed island. Pure.
///
/// An opt-in indicator, never a filler: it exists only while the Compagnon feature is on (`IslandMascotPresence`), takes
/// the wing its side setting names, and counts in that wing's width like any other item (`AmbientMetrics`). It has no text,
/// so a wing too narrow drops it before anything else (it is the last element of the wing).
enum IslandMascotIndicator {
    static let id = "mascot"
    static let label = "Compagnon"

    static func indicator(side: NotchMascotSide) -> AmbientIndicator {
        AmbientIndicator(
            id: id, channel: AmbientChannel.mascot, symbol: "face.smiling", priority: .ambient,
            wing: side == .left ? .leading : .trailing, glyph: .mascot, label: label)
    }
}

/// Keeps the companion's indicator in step with its feature: posted while `NotchMascotSupport.isEnabled()` says it is on
/// (registry switch, island hosted, its own toggle), withdrawn when it is not, re-read whenever a preference changes (the
/// side, the toggle on its page).
@MainActor
final class IslandMascotPresence {
    struct Hooks {
        var isShown: @MainActor () -> Bool
        var side: @MainActor () -> NotchMascotSide
        var post: @MainActor (AmbientIndicator) -> Void
        var withdraw: @MainActor (String) -> Void
        /// Calls `onChange` whenever a preference may have changed (live: `UserDefaults.didChangeNotification`).
        var observe: (@escaping @MainActor () -> Void) -> AnyCancellable?

        static var live: Hooks {
            Hooks(
                isShown: { NotchMascotSupport.isEnabled() },
                side: { NotchMascotSupport.side() },
                post: { AmbientCenter.shared.post($0) },
                withdraw: { AmbientCenter.shared.withdraw(id: $0) },
                observe: { onChange in
                    NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                        .receive(on: DispatchQueue.main)
                        .sink { _ in MainActor.assumeIsolated { onChange() } }
                })
        }
    }

    private let hooks: Hooks
    private var subscription: AnyCancellable?

    init(hooks: Hooks) { self.hooks = hooks }

    var isRunning: Bool { subscription != nil }

    func start() {
        guard subscription == nil else { return refresh() }
        subscription = hooks.observe { [weak self] in self?.refresh() }
        refresh()
    }

    func refresh() {
        if hooks.isShown() { hooks.post(IslandMascotIndicator.indicator(side: hooks.side())) }
        else { hooks.withdraw(IslandMascotIndicator.id) }
    }

    func stop() {
        subscription = nil
        hooks.withdraw(IslandMascotIndicator.id)
    }
}
