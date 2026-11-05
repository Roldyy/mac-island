import AppKit
import ApplicationServices
import Foundation

/// What pressing the front app's Edit > Paste item gave.
enum MenuPressResult: Equatable {
    case pressed
    case notFound        // no menu item with Cmd+V found (or no menu bar)
    case disabled        // found, but greyed out (nothing it can paste into)
    case error           // an AX call failed (no trust, app refuses, press rejected)
    case timedOut        // the app did not answer within the hard deadline
}

/// One node of a menu tree, as the finder needs it. The live implementation wraps an `AXUIElement`; tests build
/// plain values, so no real Accessibility call happens in a test.
protocol PasteMenuNode {
    var title: String { get }
    var cmdChar: String? { get }
    /// `AXMenuItemCmdModifiers` (bit 0 shift, 1 option, 2 control, 3 "no command"): 0 is Command alone.
    var cmdModifiers: Int? { get }
    var enabled: Bool { get }
    /// Menu bar item -> its menu -> its items; an item with a submenu returns the submenu's items.
    func children() -> [Self]
}

/// Strategy 1 of a plain paste: press the front app's own Paste menu item instead of posting keys. The press does not
/// depend on the physical modifiers, so it works at once while Option+Cmd are still down.
enum PasteMenuInvoker {
    /// Soft budget for walking the menus.
    static let searchBudget: TimeInterval = 0.040
    /// Hard deadline for the whole AX round trip (a hung app can block an AX call).
    static let hardDeadline: TimeInterval = 0.150
    /// Titles that are Cmd+V variants but not a plain Paste.
    static let excludedTitleParts = ["style", "format", "match", "déplacer", "deplacer"]
    /// Menu bar items searched, submenu levels followed below an item.
    static let maxSubmenuDepth = 2

    enum Found<Node> {
        case item(Node)
        case disabled
        case none
    }

    /// Pure search. `expired` is asked between nodes. The first enabled match wins; a disabled match is remembered, so
    /// "greyed out" and "not found" stay distinguishable.
    static func find<Node: PasteMenuNode>(in menuBarItems: [Node], expired: () -> Bool = { false }) -> Found<Node> {
        var sawDisabled = false
        func isPaste(_ n: Node) -> Bool {
            guard let c = n.cmdChar, c.uppercased() == "V", n.cmdModifiers == 0 else { return false }
            let t = n.title.lowercased()
            return !excludedTitleParts.contains { t.contains($0) }
        }
        func walk(_ nodes: [Node], depth: Int) -> Node? {
            for n in nodes {
                if expired() { return nil }
                if isPaste(n) {
                    if n.enabled { return n }
                    sawDisabled = true
                    continue
                }
                if depth < maxSubmenuDepth {
                    if let hit = walk(n.children(), depth: depth + 1) { return hit }
                }
            }
            return nil
        }
        if let hit = walk(menuBarItems, depth: 0) { return .item(hit) }
        return sawDisabled ? .disabled : .none
    }

    // MARK: - Live Accessibility

    /// A once-only gate between the worker and the deadline: whoever comes second finds the continuation spent. The
    /// worker marks "pressing" before it performs the action; a deadline that fires after that waits for the press
    /// (each AX call is itself bounded by the messaging timeout), so a late press can never double a fallback paste.
    private final class Gate: @unchecked Sendable {
        private enum State { case idle, pressing, done }
        private let lock = NSLock()
        private var state = State.idle
        private var continuation: CheckedContinuation<MenuPressResult, Never>?
        init(_ c: CheckedContinuation<MenuPressResult, Never>) { continuation = c }

        func beginPress() -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard state == .idle else { return false }
            state = .pressing
            return true
        }
        func finish(_ result: MenuPressResult) {
            lock.lock()
            guard state != .done, let c = continuation else { lock.unlock(); return }
            state = .done; continuation = nil
            lock.unlock()
            c.resume(returning: result)
        }
        /// Deadline: only wins while no press has started.
        func expire() {
            lock.lock()
            guard state == .idle, let c = continuation else { lock.unlock(); return }
            state = .done; continuation = nil
            lock.unlock()
            c.resume(returning: .timedOut)
        }
    }

    /// Search and press on a background queue with a hard deadline.
    static func livePress(pid: pid_t) async -> MenuPressResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<MenuPressResult, Never>) in
            let gate = Gate(continuation)
            DispatchQueue.global(qos: .userInteractive).async {
                gate.finish(pressSync(pid: pid, gate: gate))
            }
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + hardDeadline) { gate.expire() }
        }
    }

    nonisolated private static func pressSync(pid: pid_t, gate: Gate) -> MenuPressResult {
        guard AXIsProcessTrusted() else { return .error }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        var barRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &barRef) == .success,
              let barRef, CFGetTypeID(barRef) == AXUIElementGetTypeID() else { return .notFound }
        let bar = barRef as! AXUIElement   // swiftlint:disable:this force_cast
        let start = ProcessInfo.processInfo.systemUptime
        let items = LiveNode(element: bar).children()
        switch find(in: items, expired: { ProcessInfo.processInfo.systemUptime - start > searchBudget }) {
        case .none: return .notFound
        case .disabled: return .disabled
        case .item(let node):
            guard gate.beginPress() else { return .timedOut }
            let r = AXUIElementPerformAction(node.element, kAXPressAction as CFString)
            return r == .success ? .pressed : .error
        }
    }

    private struct LiveNode: PasteMenuNode {
        let element: AXUIElement

        private func value(_ name: String) -> CFTypeRef? {
            var ref: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success ? ref : nil
        }
        var title: String { value(kAXTitleAttribute) as? String ?? "" }
        var cmdChar: String? { value(kAXMenuItemCmdCharAttribute) as? String }
        var cmdModifiers: Int? { (value(kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue }
        var enabled: Bool { (value(kAXEnabledAttribute) as? NSNumber)?.boolValue ?? false }
        func children() -> [LiveNode] {
            guard let list = value(kAXChildrenAttribute) as? [AXUIElement] else { return [] }
            // A bar item (or an item with a submenu) holds one AXMenu whose children are the items.
            var out: [LiveNode] = []
            for child in list {
                let node = LiveNode(element: child)
                if (node.value(kAXRoleAttribute) as? String) == kAXMenuRole as String {
                    out.append(contentsOf: node.children())
                } else {
                    out.append(node)
                }
            }
            return out
        }
    }
}

/// The plain-paste send step: the fast Edit-menu press first, the key sequencer as the fallback.
@MainActor
struct PasteDispatcher {
    var frontPID: () -> pid_t?
    var ownPID: pid_t = ProcessInfo.processInfo.processIdentifier
    var pressMenu: (pid_t) async -> MenuPressResult
    var sendKeys: () async -> PasteSendResult
    /// Milliseconds on a monotonic clock.
    var nowMs: () -> Int = { Int(ProcessInfo.processInfo.systemUptime * 1000) }

    static func live() -> PasteDispatcher {
        PasteDispatcher(frontPID: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
                        pressMenu: { await PasteMenuInvoker.livePress(pid: $0) },
                        sendKeys: { await PasteKeySequencer.live().run() })
    }

    func run() async -> PasteSendResult {
        let start = nowMs()
        if let pid = frontPID(), pid != ownPID {
            let result = await pressMenu(pid)
            let ms = nowMs() - start
            if result == .pressed {
                PasteLog.logger.notice("paste strategy: menu press ok in \(ms, privacy: .public) ms")
                return .posted
            }
            PasteLog.logger.notice("paste strategy: menu press \(String(describing: result), privacy: .public) after \(ms, privacy: .public) ms, falling back to keys")
        } else {
            PasteLog.logger.notice("paste strategy: no other front app, using keys")
        }
        let keysStart = nowMs()
        let r = await sendKeys()
        PasteLog.logger.notice("paste strategy: keys \(r == .posted ? "posted" : "FAILED", privacy: .public) in \(self.nowMs() - keysStart, privacy: .public) ms (total \(self.nowMs() - start, privacy: .public) ms)")
        return r
    }
}
