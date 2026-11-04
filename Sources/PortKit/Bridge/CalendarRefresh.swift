// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Mac Island calendar lane (Google Calendar through the macOS account). Hand-written, never touched by import.sh.

import AppKit
import EventKit
import Foundation

/// What makes the island read its calendars again. Events are pushed by EventKit (a Google sync lands as a store
/// change); the only timer is the service's slow safety net, never a poll.
enum CalendarRefreshPolicy {
    static let storeNotifications: [Notification.Name] = [
        .EKEventStoreChanged, NSApplication.didBecomeActiveNotification,
        .NSSystemClockDidChange, .NSSystemTimeZoneDidChange, .NSCalendarDayChanged,
    ]
    /// Wake is posted on the workspace's own center, not the default one.
    static let workspaceNotifications: [Notification.Name] = [NSWorkspace.didWakeNotification]
    static let safetyInterval: TimeInterval = 900
}

/// Observes the notifications of `CalendarRefreshPolicy` and calls back; centers are injected so a test can post
/// into its own.
final class CalendarRefreshObserver {
    private let center: NotificationCenter
    private let workspaceCenter: NotificationCenter
    private let queue: OperationQueue?
    private let onChange: () -> Void
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    init(center: NotificationCenter = .default, workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         queue: OperationQueue? = .main, onChange: @escaping () -> Void) {
        self.center = center
        self.workspaceCenter = workspaceCenter
        self.queue = queue
        self.onChange = onChange
    }

    func start() {
        guard tokens.isEmpty else { return }
        for (target, names) in [(center, CalendarRefreshPolicy.storeNotifications),
                                (workspaceCenter, CalendarRefreshPolicy.workspaceNotifications)] {
            for name in names {
                tokens.append((target, target.addObserver(forName: name, object: nil, queue: queue) { [onChange] _ in onChange() }))
            }
        }
    }

    func stop() {
        tokens.forEach { $0.0.removeObserver($0.1) }
        tokens.removeAll()
    }

    deinit { stop() }
}
