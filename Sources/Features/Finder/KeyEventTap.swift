import ApplicationServices
import CoreGraphics
import Foundation

/// Active keyDown tap (listen-only cannot swallow). Its run loop source lives on a dedicated thread,
/// so a stalled main thread never delays typing in other apps. The callback does the swallow-or-pass
/// decision synchronously from a thread-safe snapshot; only a decided key (Cmd+X, Cmd+V, Esc or Cmd+C
/// in Finder) is handed to the main thread. Removable; never prompts for any permission.
@MainActor
final class KeyEventTap {
    private let box: TapBox
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var thread: TapRunLoopThread?
    private var watchdog: Timer?
    private(set) var lastFailure: String?
    var onLost: () -> Void = {}

    var isRunning: Bool { tap != nil }

    /// `decide` runs on the tap thread and must stay cheap and thread-safe; `perform` runs on the main
    /// actor, in key order, for every decision that is not `.pass`.
    init(decide: @escaping @Sendable (KeyChord) -> KeyDecision,
         perform: @escaping @MainActor (KeyDecision) -> Void) {
        box = TapBox(decide: decide, onMain: { decision in
            DispatchQueue.main.async { MainActor.assumeIsolated { perform(decision) } }
        })
    }

    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }
    static var inputMonitoringGranted: Bool { CGPreflightListenEventAccess() }

    /// Idempotent. False when a permission is missing or macOS refused the tap.
    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        guard Self.accessibilityTrusted, Self.inputMonitoringGranted else {
            lastFailure = "permission"; return false
        }
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            // Runs on the tap thread: no main-actor access here.
            return Unmanaged<TapBox>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .defaultTap, eventsOfInterest: mask,
                                           callback: callback,
                                           userInfo: Unmanaged.passUnretained(box).toOpaque()) else {
            lastFailure = "refused"; return false
        }
        let worker = TapRunLoopThread(keepAlive: box)
        worker.name = "mac-island.finder.keytap"
        worker.qualityOfService = .userInteractive
        worker.start()
        guard let runLoop = worker.waitUntilReady() else {
            CFMachPortInvalidate(port)
            worker.shutdown()
            lastFailure = "refused"; return false
        }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(runLoop, src, .commonModes)
        box.setPort(port)
        CGEvent.tapEnable(tap: port, enable: true)
        worker.resume()
        tap = port
        source = src
        thread = worker
        lastFailure = nil
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAlive() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
        return true
    }

    func stop() {
        watchdog?.invalidate(); watchdog = nil
        if let src = source, let runLoop = thread?.runLoop { CFRunLoopRemoveSource(runLoop, src, .commonModes) }
        if let port = tap {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        box.setPort(nil)
        thread?.shutdown()
        thread = nil
        source = nil
        tap = nil
    }

    /// Safety net next to the callback path: re-enable a tap macOS switched off, drop it if trust went away.
    private func checkAlive() {
        guard let tap else { return }
        if !Self.accessibilityTrusted || !Self.inputMonitoringGranted {
            stop(); onLost(); return
        }
        if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
    }
}

/// What the C callback reaches: the decision closure, the hop to the main thread and the port (for the
/// watchdog re-enable). Touched from the tap thread and the main thread, so every field is immutable
/// or behind the lock.
private final class TapBox: @unchecked Sendable {
    private let decide: @Sendable (KeyChord) -> KeyDecision
    private let onMain: @Sendable (KeyDecision) -> Void
    private let lock = NSLock()
    private var port: CFMachPort?

    init(decide: @escaping @Sendable (KeyChord) -> KeyDecision, onMain: @escaping @Sendable (KeyDecision) -> Void) {
        self.decide = decide
        self.onMain = onMain
    }

    func setPort(_ new: CFMachPort?) { lock.lock(); port = new; lock.unlock() }

    private func reenable() {
        lock.lock(); let current = port; lock.unlock()
        if let current { CGEvent.tapEnable(tap: current, enable: true) }
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if TapWatchdog.shouldReenable(disabledByTimeout: type == .tapDisabledByTimeout,
                                      disabledByUserInput: type == .tapDisabledByUserInput) {
            reenable()
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        let flags = event.flags
        let chord = KeyChord(keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
                             command: flags.contains(.maskCommand), shift: flags.contains(.maskShift),
                             option: flags.contains(.maskAlternate), control: flags.contains(.maskControl),
                             isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        guard KeyDecision.isCandidate(chord) else { return Unmanaged.passUnretained(event) }
        let decision = decide(chord)
        guard decision != .pass else { return Unmanaged.passUnretained(event) }
        onMain(decision)
        return decision.swallows ? nil : Unmanaged.passUnretained(event)
    }
}

/// A thread that only runs a run loop, so the tap's source never competes with the UI.
private final class TapRunLoopThread: Thread, @unchecked Sendable {
    private let ready = DispatchSemaphore(value: 0)
    private let go = DispatchSemaphore(value: 0)
    /// Written once before `ready` is signalled.
    private(set) var runLoop: CFRunLoop?
    private let keepAlive: AnyObject

    init(keepAlive: AnyObject) {
        self.keepAlive = keepAlive
        super.init()
    }

    override func main() {
        runLoop = CFRunLoopGetCurrent()
        ready.signal()
        go.wait()
        while !isCancelled { _ = CFRunLoopRunInMode(.defaultMode, 1, false) }
    }

    func waitUntilReady() -> CFRunLoop? {
        guard ready.wait(timeout: .now() + 2) == .success else { return nil }
        return runLoop
    }
    func resume() { go.signal() }
    func shutdown() {
        cancel()
        if let runLoop { CFRunLoopStop(runLoop) }
        go.signal()
    }
}
