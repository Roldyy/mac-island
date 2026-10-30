import Foundation

struct AutoQuitConfig: Equatable {
    var delay: TimeInterval
    var userExclusions: Set<String>
    var ownPID: Int32

    /// Never quit, whatever the user lists. Menu-bar helper agents are excluded by `isRegular`.
    static let builtInExclusions: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.systemuiserver",
        "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.Spotlight",
        "com.apple.WindowManager", "be.roldy.macisland",
    ]
}

/// Pure decision: which apps have been idle long enough. No clock, no system calls.
enum AutoQuitPlanner {
    static func candidates(apps: [AppSnapshot], lastActive: [Int32: Date], now: Date,
                           monitoringSince: Date, config: AutoQuitConfig) -> [AppSnapshot] {
        // Never act before one full interval of observation, whatever the tracker says.
        guard now.timeIntervalSince(monitoringSince) >= config.delay else { return [] }
        return apps.filter { app in
            guard app.isRegular, app.pid != config.ownPID,
                  let bundle = app.bundleID,
                  !AutoQuitConfig.builtInExclusions.contains(bundle),
                  !config.userExclusions.contains(bundle),
                  !app.isFrontmost, !app.isPlayingAudio, app.windowCount == 0,
                  let last = lastActive[app.pid] else { return false }
            return now.timeIntervalSince(last) >= config.delay
        }
        .sorted { $0.pid < $1.pid }
    }
}
