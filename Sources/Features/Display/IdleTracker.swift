import Foundation

/// Remembers, per pid, the last time an app was seen busy (window, frontmost or audio).
/// First sighting counts as active, so a fresh launch never inherits an old idle time.
struct IdleTracker: Equatable {
    private(set) var lastActive: [Int32: Date] = [:]

    mutating func update(_ apps: [AppSnapshot], now: Date) {
        var next: [Int32: Date] = [:]
        for app in apps {
            if app.windowCount > 0 || app.isFrontmost || app.isPlayingAudio {
                next[app.pid] = now
            } else {
                next[app.pid] = lastActive[app.pid] ?? now
            }
        }
        lastActive = next
    }

    mutating func reset() { lastActive = [:] }
}
