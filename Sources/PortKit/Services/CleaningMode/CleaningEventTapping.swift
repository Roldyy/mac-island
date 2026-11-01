// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import AppKit
import CoreGraphics

/// One input event, reduced to what cleaning mode decides on. The system tap translates a `CGEvent` into this;
/// a test feeds it straight to the manager through a fake tap.
enum CleaningInput: Equatable {
    case key(code: Int64, isDown: Bool, isRepeat: Bool)
    /// Shift, control, option, command, fn, caps lock: the keys nearest Escape.
    case flagsChanged(code: Int64)
    case systemKey(CleaningSystemKeyEvent)
    case mouseButton(button: Int64, isDown: Bool)
    /// Scrolling, gestures and anything else the lock swallows.
    case other
    /// The system switched the tap off (it stalled, or user input disabled it).
    case tapDisabled
}

/// The event tap of cleaning mode, behind a protocol so the manager can be driven without a permission.
protocol CleaningEventTapping: AnyObject {
    /// Starts the tap. `deliver` runs on the main thread for each event and answers true when the event is
    /// swallowed. Returns false when the tap cannot exist: nothing is then swallowed.
    func start(deliver: @escaping (CleaningInput) -> Bool) -> Bool
    func stop()
    /// False once the system switched the tap off behind our back.
    var isEnabled: Bool { get }
}

/// The real tap: HID level, head of the chain, active. Its run loop source lives on the main run loop, so the
/// callback runs on the main thread. If that thread stalls, the system disables the tap and the keyboard
/// comes back by itself, which the manager also treats as the end of cleaning.
final class SystemCleaningTap: CleaningEventTapping {
    private static let systemDefined = CGEventType(rawValue: CleaningSystemKeyEvent.systemDefinedEventTypeRawValue)!
    private static let gesture = CGEventType(rawValue: UInt32(NSEvent.EventType.gesture.rawValue))!
    private static let mask: CGEventMask = [
        CGEventType.keyDown, .keyUp, .flagsChanged, .scrollWheel,
        .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
        systemDefined, gesture,
    ].reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var deliver: ((CleaningInput) -> Bool)?

    var isEnabled: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start(deliver: @escaping (CleaningInput) -> Bool) -> Bool {
        stop()
        self.deliver = deliver
        guard let created = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: Self.mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<SystemCleaningTap>.fromOpaque(userInfo).takeUnretainedValue()
                return tap.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            self.deliver = nil
            return false
        }
        tap = created
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        return true
    }

    func stop() {
        deliver = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let deliver else { return Unmanaged.passUnretained(event) }
        let swallowed = deliver(Self.input(type: type, event: event))
        return swallowed ? nil : Unmanaged.passUnretained(event)
    }

    private static func input(type: CGEventType, event: CGEvent) -> CleaningInput {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            return .tapDisabled
        case .keyDown, .keyUp:
            return .key(code: event.getIntegerValueField(.keyboardEventKeycode),
                        isDown: type == .keyDown,
                        isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        case .flagsChanged:
            return .flagsChanged(code: event.getIntegerValueField(.keyboardEventKeycode))
        case .leftMouseDown, .leftMouseUp:
            return .mouseButton(button: 0, isDown: type == .leftMouseDown)
        case .rightMouseDown, .rightMouseUp:
            return .mouseButton(button: 1, isDown: type == .rightMouseDown)
        case .otherMouseDown, .otherMouseUp:
            return .mouseButton(button: event.getIntegerValueField(.mouseEventButtonNumber),
                                isDown: type == .otherMouseDown)
        default:
            if type == systemDefined, let ns = NSEvent(cgEvent: event),
               let key = CleaningSystemKeyEvent.decode(subtype: Int(ns.subtype.rawValue), data1: ns.data1) {
                return .systemKey(key)
            }
            return .other
        }
    }
}
