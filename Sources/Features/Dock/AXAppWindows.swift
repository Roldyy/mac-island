import AppKit
import ApplicationServices

@MainActor
final class AXAppWindows: AppWindowAccessing {
    private func elements(pid: Int32) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        return AX.elements(app, kAXWindowsAttribute as String).filter {
            // Skip palettes, sheets and other non-document windows.
            AX.string($0, kAXSubroleAttribute as String) == (kAXStandardWindowSubrole as String)
        }
    }

    func windows(pid: Int32) -> [DockWindow] {
        elements(pid: pid).map {
            DockWindow(title: AX.string($0, kAXTitleAttribute as String) ?? "",
                       frame: AX.frame($0) ?? .zero,
                       isMinimized: AX.bool($0, kAXMinimizedAttribute as String) ?? false,
                       isFullScreen: AX.bool($0, "AXFullScreen") ?? false)
        }
    }

    func perform(_ action: DockClickAction, pid: Int32) {
        let els = elements(pid: pid)
        switch action {
        case .none: break
        case .minimizeAll:
            for e in els where !(AX.bool(e, kAXMinimizedAttribute as String) ?? false) {
                AX.set(e, kAXMinimizedAttribute as String, true)
            }
        case .restoreAll:
            var first: AXUIElement?
            for e in els where AX.bool(e, kAXMinimizedAttribute as String) ?? false {
                AX.set(e, kAXMinimizedAttribute as String, false)
                first = first ?? e
            }
            if let first { focus(first, pid: pid) }
        case .hide:
            NSRunningApplication(processIdentifier: pid)?.hide()
        case let .cycle(index):
            if els.indices.contains(index) { focus(els[index], pid: pid) }
        }
    }

    func raise(pid: Int32, windowAt index: Int) {
        let els = elements(pid: pid)
        guard els.indices.contains(index) else { return }
        if AX.bool(els[index], kAXMinimizedAttribute as String) ?? false {
            AX.set(els[index], kAXMinimizedAttribute as String, false)
        }
        focus(els[index], pid: pid)
    }

    private func focus(_ window: AXUIElement, pid: Int32) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AX.set(window, kAXMainAttribute as String, true)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }
}

@MainActor
final class SystemWorkspace: WorkspaceQuerying {
    var frontmostBundleID: String? { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    func isHidden(pid: Int32) -> Bool { NSRunningApplication(processIdentifier: pid)?.isHidden ?? false }
}
