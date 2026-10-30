import ApplicationServices
import CoreGraphics
import Foundation

/// Active keyDown tap (listen-only cannot swallow). Installed on the main run loop, so the callback
/// and the handler run on the main thread. Removable; never prompts for any permission.
@MainActor
final class KeyEventTap {
    /// Returns true to swallow the event.
    private let handler: @MainActor (KeyChord) -> Bool
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var watchdog: Timer?
    private(set) var lastFailure: String?
    var onLost: () -> Void = {}

    var isRunning: Bool { tap != nil }

    init(handler: @escaping @MainActor (KeyChord) -> Bool) { self.handler = handler }

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
            let me = Unmanaged<KeyEventTap>.fromOpaque(refcon).takeUnretainedValue()
            // Registered on the main run loop: this is the main thread.
            return MainActor.assumeIsolated { me.handle(type: type, event: event) }
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .defaultTap, eventsOfInterest: mask,
                                           callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            lastFailure = "refused"; return false
        }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        source = src
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
        if let src = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        if let port = tap {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        source = nil
        tap = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if TapWatchdog.shouldReenable(disabledByTimeout: type == .tapDisabledByTimeout,
                                      disabledByUserInput: type == .tapDisabledByUserInput) {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        let flags = event.flags
        let chord = KeyChord(keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
                             command: flags.contains(.maskCommand), shift: flags.contains(.maskShift),
                             option: flags.contains(.maskAlternate), control: flags.contains(.maskControl),
                             isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        return handler(chord) ? nil : Unmanaged.passUnretained(event)
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
