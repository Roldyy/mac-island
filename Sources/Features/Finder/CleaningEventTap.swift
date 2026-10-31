import ApplicationServices
import CoreGraphics
import Foundation

/// Active tap that drops every keyboard, mouse and scroll event while cleaning. Like `KeyEventTap`, its
/// run loop source lives on a dedicated thread; unlike it, the callback also stops swallowing by itself
/// once the deadline passed, so a stalled main thread can never lock the user out. Never prompts.
@MainActor
final class CleaningEventTap: CleaningTapping {
    private let box = CleaningTapBox()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var thread: CleaningRunLoopThread?
    private var watchdog: Timer?

    var onEscape: (_ down: Bool, _ isRepeat: Bool) -> Void = { _, _ in }
    var onLost: () -> Void = {}

    func start(deadline: TimeInterval) -> CleaningStartFailure? {
        guard AXIsProcessTrusted() else { return .needsAccessibility }
        guard CGPreflightListenEventAccess() else { return .needsInputMonitoring }
        stop()
        box.configure(deadline: deadline) { [weak self] down, rep in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.onEscape(down, rep) } }
        }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            return Unmanaged<CleaningTapBox>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .defaultTap, eventsOfInterest: ~CGEventMask(0),
                                           callback: callback,
                                           userInfo: Unmanaged.passUnretained(box).toOpaque()) else { return .refused }
        let worker = CleaningRunLoopThread(keepAlive: box)
        worker.name = "mac-island.cleaning.tap"
        worker.qualityOfService = .userInteractive
        worker.start()
        guard let runLoop = worker.waitUntilReady() else {
            CFMachPortInvalidate(port)
            worker.shutdown()
            return .refused
        }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(runLoop, src, .commonModes)
        box.setPort(port)
        CGEvent.tapEnable(tap: port, enable: true)
        worker.resume()
        tap = port
        source = src
        thread = worker
        // Trust revoked or the tap switched off by macOS: give the keyboard back at once.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAlive() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
        return nil
    }

    func stop() {
        watchdog?.invalidate()
        watchdog = nil
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

    private func checkAlive() {
        guard let tap else { return }
        if !AXIsProcessTrusted() || !CGEvent.tapIsEnabled(tap: tap) { onLost() }
    }
}

/// What the C callback reaches. Touched from the tap thread and the main thread: immutable or locked.
private final class CleaningTapBox: @unchecked Sendable {
    private let lock = NSLock()
    private var port: CFMachPort?
    private var deadline: TimeInterval = 0
    private var onEscape: (@Sendable (Bool, Bool) -> Void)?

    func configure(deadline: TimeInterval, onEscape: @escaping @Sendable (Bool, Bool) -> Void) {
        lock.lock(); self.deadline = deadline; self.onEscape = onEscape; lock.unlock()
    }

    func setPort(_ new: CFMachPort?) { lock.lock(); port = new; lock.unlock() }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        lock.lock(); let current = port; let limit = deadline; let notify = onEscape; lock.unlock()
        if type == .tapDisabledByTimeout {
            if let current { CGEvent.tapEnable(tap: current, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByUserInput { return Unmanaged.passUnretained(event) }  // the watchdog ends the session
        guard CleaningPolicy.swallows(uptime: ProcessInfo.processInfo.systemUptime, deadline: limit) else {
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown || type == .keyUp,
           Int(event.getIntegerValueField(.keyboardEventKeycode)) == CleaningPolicy.escapeKeyCode {
            notify?(type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        }
        return nil
    }
}

/// A thread that only runs a run loop, so the tap never competes with the UI.
private final class CleaningRunLoopThread: Thread, @unchecked Sendable {
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
