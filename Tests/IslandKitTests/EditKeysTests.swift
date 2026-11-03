import AppKit
import Testing
@testable import IslandKit

/// Harold, 2026-11-03: Cmd+C / X / V / A / Z do nothing in the island's text inputs (the Brouillon). The app is an accessory app
/// with no Edit menu and the panel is non-activating, so no key equivalent ever reached the text view. These tests send the
/// real events through `NSPanel.performKeyEquivalent`, the path AppKit takes for every command-key press.
@MainActor
@Suite struct EditKeysTests {
    /// Records the three actions that would touch the user's clipboard, so the suite never writes to it.
    private final class SpyTextView: NSTextView {
        var calls: [String] = []
        override func copy(_ sender: Any?) { calls.append("copy") }
        override func cut(_ sender: Any?) { calls.append("cut") }
        override func paste(_ sender: Any?) { calls.append("paste") }
    }

    private struct Rig {
        let panel: NotchPanel
        let text: SpyTextView
    }

    private func rig(_ string: String = "hello world") -> Rig {
        let panel = NotchPanel()
        panel.acceptsKeyboard = true
        let text = SpyTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        text.isEditable = true
        text.isSelectable = true
        text.allowsUndo = true
        text.string = string
        panel.contentView = text
        panel.setFrame(NSRect(x: 0, y: 0, width: 300, height: 100), display: false)
        _ = panel.makeFirstResponder(text)
        return Rig(panel: panel, text: text)
    }

    private func keyEvent(_ char: String, keyCode: UInt16, _ flags: NSEvent.ModifierFlags, window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                         windowNumber: window.windowNumber, context: nil, characters: char,
                         charactersIgnoringModifiers: char, isARepeat: false, keyCode: keyCode)!
    }

    @Test func commandAKeyEquivalentSelectsAll() {
        let r = rig()
        r.text.setSelectedRange(NSRange(location: 0, length: 0))
        let handled = r.panel.performKeyEquivalent(with: keyEvent("a", keyCode: 0, .command, window: r.panel))
        #expect(handled)
        #expect(r.text.selectedRange() == NSRange(location: 0, length: 11))
    }

    @Test func commandCXV_reachTheFocusedTextView() {
        let r = rig()
        #expect(r.panel.performKeyEquivalent(with: keyEvent("c", keyCode: 8, .command, window: r.panel)))
        #expect(r.panel.performKeyEquivalent(with: keyEvent("x", keyCode: 7, .command, window: r.panel)))
        #expect(r.panel.performKeyEquivalent(with: keyEvent("v", keyCode: 9, .command, window: r.panel)))
        #expect(r.text.calls == ["copy", "cut", "paste"])
    }

    @Test func commandZUndoesAndCommandShiftZRedoes() {
        let r = rig("")
        r.text.setSelectedRange(NSRange(location: 0, length: 0))
        r.text.undoManager?.groupsByEvent = false
        r.text.undoManager?.beginUndoGrouping()
        r.text.insertText("abc", replacementRange: NSRange(location: 0, length: 0))
        r.text.undoManager?.endUndoGrouping()
        #expect(r.text.string == "abc")
        #expect(r.panel.performKeyEquivalent(with: keyEvent("z", keyCode: 6, .command, window: r.panel)))
        #expect(r.text.string == "")
        #expect(r.panel.performKeyEquivalent(with: keyEvent("Z", keyCode: 6, [.command, .shift], window: r.panel)))
        #expect(r.text.string == "abc")
    }

    @Test func optionCommandVIsLeftToTheHotkey() {
        let r = rig()
        let handled = r.panel.performKeyEquivalent(with: keyEvent("v", keyCode: 9, [.command, .option], window: r.panel))
        #expect(!handled)
        #expect(r.text.calls.isEmpty)
    }

    @Test func aNonTextResponderIsLeftAlone() {
        // The terminal is not an NSText: its own copy / paste handling must be the only one that answers.
        let r = rig()
        let other = NSView()
        r.panel.contentView?.addSubview(other)
        let handled = r.panel.performKeyEquivalent(with: keyEvent("c", keyCode: 8, .command, window: r.panel))
        #expect(handled)  // the text view still answers while it is first responder
        r.text.calls.removeAll()
        class Plain: NSView { override var acceptsFirstResponder: Bool { true } }
        let plain = Plain()
        r.panel.contentView?.addSubview(plain)
        #expect(r.panel.makeFirstResponder(plain))
        #expect(!r.panel.performKeyEquivalent(with: keyEvent("c", keyCode: 8, .command, window: r.panel)))
        #expect(r.text.calls.isEmpty)
    }

    @Test func markedTextIsNotInterrupted() {
        let r = rig("")
        r.text.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: 0, length: 0))
        #expect(r.text.hasMarkedText())
        #expect(!r.panel.performKeyEquivalent(with: keyEvent("v", keyCode: 9, .command, window: r.panel)))
        #expect(r.text.calls.isEmpty)
    }

    @Test func commandArrowsAndOptionArrowsMoveTheCaret() {
        // Not key equivalents: they travel keyDown -> interpretKeyEvents, which already works. Pinned so it stays so.
        let r = rig("one two three")
        r.text.setSelectedRange(NSRange(location: 13, length: 0))
        let left: UInt16 = 123
        let leftKey = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        r.text.keyDown(with: keyEvent(leftKey, keyCode: left, [.option, .function], window: r.panel))
        #expect(r.text.selectedRange().location == 8)  // start of "three"
        r.text.keyDown(with: keyEvent(leftKey, keyCode: left, [.command, .function], window: r.panel))
        #expect(r.text.selectedRange().location == 0)
    }

    @Test func installedEditMenuAnswersTheStandardKeys() {
        EditMenu.install()
        let main = NSApplication.shared.mainMenu
        #expect(main != nil)
        let items = main?.items.compactMap(\.submenu).flatMap(\.items) ?? []
        let keys = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.action.map { (NSStringFromSelector($0), item) }
        })
        for (action, key, flags) in [("copy:", "c", NSEvent.ModifierFlags.command), ("cut:", "x", .command),
                                     ("paste:", "v", .command), ("selectAll:", "a", .command),
                                     ("undo:", "z", .command), ("redo:", "z", [.command, .shift])] {
            #expect(keys[action]?.keyEquivalent.lowercased() == key, "\(action)")
            #expect(keys[action]?.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control]) == flags,
                    "\(action)")
        }
        // Idempotent: a second call neither duplicates the Edit menu nor replaces a menu the app already has.
        let count = NSApplication.shared.mainMenu?.items.count
        EditMenu.install()
        #expect(NSApplication.shared.mainMenu?.items.count == count)
    }
}
