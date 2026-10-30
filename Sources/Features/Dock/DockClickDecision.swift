import Foundation

struct DockClickOptions: Equatable, Sendable {
    var minimize: Bool
    var hide: Bool
    var cycle: Bool
    var anyEnabled: Bool { minimize || hide || cycle }
}

/// One window of an app, as read through Accessibility. Title and frame are for the preview only: never logged.
struct DockWindow: Equatable, Sendable {
    var title: String = ""
    var frame: CGRect = .zero
    var isMinimized = false
    var isFullScreen = false
}

struct DockClickInput: Equatable, Sendable {
    var options: DockClickOptions
    var clickedBundleID: String?
    var frontmostBundleID: String?
    /// Front to back, as Accessibility lists them.
    var windows: [DockWindow]
    var isHidden: Bool
}

enum DockClickAction: Equatable, Sendable {
    case none
    case minimizeAll
    case restoreAll
    case hide
    /// Raise the window at this index of the Accessibility list.
    case cycle(raiseWindowAt: Int)
}

enum DockClickDecision {
    static let dockBundleID = "com.apple.dock"

    static func decide(_ i: DockClickInput) -> DockClickAction {
        guard i.options.anyEnabled, let clicked = i.clickedBundleID, clicked != dockBundleID else { return .none }
        guard !i.isHidden, !i.windows.isEmpty else { return .none }
        // Full screen lives in its own Space: minimizing there only gets in the way.
        guard !i.windows.contains(where: \.isFullScreen) else { return .none }

        let visible = i.windows.indices.filter { !i.windows[$0].isMinimized }
        if visible.isEmpty { return i.options.minimize ? .restoreAll : .none }
        // Not frontmost: the system activates the app, nothing to add.
        guard clicked == i.frontmostBundleID else { return .none }

        if i.options.cycle, visible.count >= 2, let rearmost = visible.last { return .cycle(raiseWindowAt: rearmost) }
        if i.options.minimize { return .minimizeAll }
        if i.options.hide { return .hide }
        return .none
    }
}
