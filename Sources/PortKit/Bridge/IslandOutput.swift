// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W8A/W8B (island activities, group 1). New file of the lane: the one place where the ported island services
// (timer, accessories, notifications, lyrics, queue, calendar) reach OUR island.

import Foundation
import IslandKit
import IslandUI

extension PortHost {
    /// True while a bridge lane hosts the ported island features (timer, calendar, accessories, notifications,
    /// lyrics, queue) in Mac Island's own island. Read by `NotchSupport.hostsFeatures` (patch 1600): those features
    /// then run although Vorssaint's own island window stays asleep (`vorssaintIslandEnabled`, always off).
    public nonisolated(unsafe) static var hostsIslandFeatures = false
}

/// Who currently hosts ported island features. A lane acquires when its feature starts (or its tab is on screen)
/// and releases when it stops, so the flag is false again once nothing needs it.
@MainActor
enum PortIslandHosting {
    private static var owners: Set<String> = []

    static func acquire(_ owner: String) {
        owners.insert(owner)
        PortHost.hostsIslandFeatures = true
    }

    static func release(_ owner: String) {
        owners.remove(owner)
        PortHost.hostsIslandFeatures = !owners.isEmpty
    }

    static var isHosting: Bool { !owners.isEmpty }

    /// Tests only: forget every owner.
    static func reset() {
        owners = []
        PortHost.hostsIslandFeatures = false
    }
}

/// What a ported notice becomes in the closed island. Pure.
///
/// A notice (timer finished, an accessory connected or low, a mirrored system notification) is an ALERT of the
/// activity engine: it has a glyph AND a short text (never an icon alone), it lasts `NotchEvent.duration`, and it
/// goes away with its feature (`source` is the registry id, so a switch-off or the kill switch withdraws it).
/// It only exists while its feature is on, which the user has to do on purpose (every ported feature starts off).
enum IslandNoticeMapper {
    /// A wing has little room; the rest is for the open island.
    static let maximumLength = 24

    struct Mapped: Equatable {
        let activity: IslandActivity
        let lifetime: Duration
    }

    static func activity(for notice: NotchNotice) -> Mapped? {
        let source: String
        let text: String
        let status: IslandStatus
        switch notice.event {
        case .timer:
            source = AppFeature.notchTimer.registryID
            text = notice.title.isEmpty ? notice.detail : notice.title
            status = .success
        case .accessory:
            source = AppFeature.notchAccessories.registryID
            if let level = notice.level {
                let percent = Int((min(max(level, 0), 1) * 100).rounded())
                text = [notice.title, "\(percent) %"].filter { !$0.isEmpty }.joined(separator: " ")
                status = percent < 10 ? .danger : .warning
            } else {
                text = notice.detail.isEmpty ? notice.title : notice.detail
                status = .info
            }
        case .systemNotification:
            source = AppFeature.notchNotifications.registryID
            if let content = notice.notification {
                text = content.compactTitle
            } else {
                text = notice.title.isEmpty ? notice.detail : notice.title
            }
            status = .info
        default:
            return nil  // volume, brightness, clipboard... belong to other lanes
        }
        let shown = shortened(text)
        guard !shown.isEmpty else { return nil }
        let symbol = notice.symbol.isEmpty ? status.symbol : notice.symbol
        let activity = IslandActivity(
            id: "island.notice.\(notice.event.rawValue)", source: source, priority: .alert,
            leading: CompactItem(symbol: symbol, text: shown, status: status, progress: notice.level), showsDot: true)
        return Mapped(activity: activity, lifetime: .seconds(notice.event.duration))
    }

    static func shortened(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maximumLength else { return trimmed }
        return String(trimmed.prefix(maximumLength - 1)) + "…"
    }
}

/// The sink of `NotchService.show` while Vorssaint's island is asleep (patch 1600).
@MainActor
final class PortIslandOutput {
    static let shared = PortIslandOutput()

    /// Where activities go. The app's center in production; a recorder in tests.
    var post: (IslandActivity, Duration) -> Void = { ActivityCenter.shared.post($0, expiresAfter: $1) }
    /// Whether the feature behind a notice event is on, read from the ported support types.
    var isRouted: (NotchEvent) -> Bool = PortIslandOutput.liveRouting

    static func liveRouting(_ event: NotchEvent) -> Bool {
        let defaults = PortHost.defaults
        guard defaults.bool(forKey: event.preferenceKey) else { return false }
        switch event {
        case .timer: return NotchTimerSupport.isEnabled(in: defaults)
        case .accessory: return NotchAccessorySupport.isEnabled(in: defaults)
        case .systemNotification: return NotchNotificationSupport.isEnabled(in: defaults)
        default: return false
        }
    }

    /// Accepts a notice of a hosted feature that is switched on; refuses every other (they are other lanes').
    @discardableResult
    func present(_ notice: NotchNotice) -> Bool {
        guard isRouted(notice.event), let mapped = IslandNoticeMapper.activity(for: notice) else { return false }
        post(mapped.activity, mapped.lifetime)
        return true
    }

    /// Entry point of the patched, non-isolated `NotchService.show`. The ported services call it from the main
    /// queue; from anywhere else the notice hops there and is reported as taken.
    nonisolated static func present(fromAnyThread notice: NotchNotice) -> Bool {
        if Thread.isMainThread { return MainActor.assumeIsolated { shared.present(notice) } }
        DispatchQueue.main.async { MainActor.assumeIsolated { _ = shared.present(notice) } }
        return true
    }
}
