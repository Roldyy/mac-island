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
    /// On-screen layer-0 windows owned by the app.
    var windowCount: Int
}
