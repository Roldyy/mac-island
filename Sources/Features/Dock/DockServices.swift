import CoreGraphics
import Foundation

/// A running app's Dock icon, identified by bundle id and pid only.
struct DockApp: Equatable, Sendable {
    var bundleID: String
    var pid: Int32
    /// Cocoa coordinates.
    var iconFrame: CGRect
}

/// System seams: real implementations are in AX*.swift, fakes in the tests.
@MainActor protocol DockItemResolving: AnyObject {
    /// The running app whose Dock icon is under `point` (Cocoa coordinates), if any.
    func app(at point: CGPoint) -> DockApp?
}

@MainActor protocol AppWindowAccessing: AnyObject {
    func windows(pid: Int32) -> [DockWindow]
    func perform(_ action: DockClickAction, pid: Int32)
    func raise(pid: Int32, windowAt index: Int)
}

@MainActor protocol WorkspaceQuerying: AnyObject {
    var frontmostBundleID: String? { get }
    func isHidden(pid: Int32) -> Bool
}

enum MouseEvent: Equatable {
    case down(CGPoint)
    case moved(CGPoint)
}

/// Cocoa-coordinate mouse events from outside the app. Monitoring only: clicks are never swallowed.
@MainActor protocol MouseEventSource: AnyObject {
    var isRunning: Bool { get }
    func start(_ handler: @escaping (MouseEvent) -> Void)
    func stop()
}
