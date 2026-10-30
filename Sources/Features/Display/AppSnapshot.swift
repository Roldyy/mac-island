import Foundation

/// One running app at scan time. `name` is for the tab only and is never logged.
struct AppSnapshot: Equatable, Sendable {
    var pid: Int32
    var bundleID: String?
    var name: String
    /// `NSApplication.ActivationPolicy.regular`: a Dock app. Agents and accessories are false.
    var isRegular: Bool
    var isFrontmost: Bool
    var isPlayingAudio: Bool
    /// Layer-0 windows owned by the app, whatever their state (minimized and other-Space ones count).
    var windowCount: Int
    /// Hidden with Cmd+H: its windows are off screen but the app is in use.
    var isHidden: Bool = false
}
