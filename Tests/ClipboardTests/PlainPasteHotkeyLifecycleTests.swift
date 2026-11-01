import AppKit
import Foundation
import Testing
@testable import ClipboardFeature

/// Records registrations instead of calling Carbon.
@MainActor
final class FakeHotkey: PlainPasteHotkeyRegistering {
    var onTrigger: () -> Void = {}
    private(set) var registered: HotkeyShortcut?
    private(set) var registerCalls: [HotkeyShortcut] = []
    var accept = true

    func register(_ shortcut: HotkeyShortcut) -> Bool {
        registerCalls.append(shortcut)
        guard accept else { registered = nil; return false }
        registered = shortcut
        return true
    }
    func unregister() { registered = nil }
    func press() { onTrigger() }
}

@Suite @MainActor struct PlainPasteHotkeyLifecycleTests {
    final class Counter { var value = 0 }

    struct Rig {
        let model: ClipboardModel
        let hotkey: FakeHotkey
        let pasteboard: NSPasteboard
        let defaults: TempDefaults
        let sent: Counter
    }

    func rig(stored: String? = "option+command:9", enabled: Bool? = true, trusted: Bool = true) -> Rig {
        let td = TempDefaults()
        if let stored { td.defaults.set(stored, forKey: "pastePlainShortcut") }
        if let enabled { td.defaults.set(enabled, forKey: "pastePlainEnabled") }
        let hotkey = FakeHotkey()
        let pb = makePasteboard()
        let sent = Counter()
        let model = ClipboardModel(dataDirectory: makeTempDir(), pasteboard: pb,
                                   settings: { ClipboardSettings(defaults: td.defaults) },
                                   accessibilityTrusted: { trusted }, sendPaste: { sent.value += 1 },
                                   hotkey: hotkey)
        return Rig(model: model, hotkey: hotkey, pasteboard: pb, defaults: td, sent: sent)
    }

    func putRichText(_ pb: NSPasteboard, plain: String = "Bonjour le monde") {
        pb.clearContents()
        pb.setString(plain, forType: .string)
        pb.setData(Data("{\\rtf1\\ansi \\b Bonjour\\b0  le monde}".utf8), forType: .rtf)
        pb.setString("<p><b>Bonjour</b> le monde</p>", forType: .html)
    }

    @Test func vorssaintFormValueRegistersOptionCommandV() {
        let r = rig()
        r.model.start()
        let s = r.hotkey.registered
        #expect(s?.keyCode == 9)               // V, not the digit 9 (25)
        #expect(s?.modifiers == [.option, .command])
        #expect(r.hotkey.registerCalls.count == 1)
    }

    @Test func pressingTheHotkeyRunsPlainPasteAndStripsFormatting() async {
        let r = rig()
        r.model.start()
        putRichText(r.pasteboard)
        r.hotkey.press()
        #expect(r.pasteboard.string(forType: .string) == "Bonjour le monde")
        #expect(r.pasteboard.data(forType: .rtf) == nil)
        #expect(r.pasteboard.string(forType: .html) == nil)
        #expect(await eventually { r.sent.value == 1 })
    }

    @Test func featureOffRegistersNothing() {
        let r = rig(enabled: false)
        r.model.start()
        #expect(r.hotkey.registered == nil)
        #expect(r.hotkey.registerCalls.isEmpty)
    }

    @Test func switchingTheSettingOffAndOnFollowsLive() {
        let r = rig()
        r.model.start()
        r.defaults.defaults.set(false, forKey: "pastePlainEnabled")
        r.model.start()                         // the registry's restart reconciles
        #expect(r.hotkey.registered == nil)
        r.defaults.defaults.set(true, forKey: "pastePlainEnabled")
        r.model.start()
        #expect(r.hotkey.registered?.keyCode == 9)
    }

    @Test func changedShortcutMovesTheHotkey() {
        let r = rig()
        r.model.start()
        r.defaults.defaults.set("control+option+command:40", forKey: "pastePlainShortcut")
        r.model.start()
        #expect(r.hotkey.registered?.keyCode == 40)
        #expect(r.hotkey.registered?.modifiers == [.control, .option, .command])
    }

    @Test func stopThenStartRegistersAgainAndStillPastes() async {
        let r = rig()
        r.model.start()
        r.model.stop()
        #expect(r.hotkey.registered == nil)
        r.model.start()
        #expect(r.hotkey.registered?.keyCode == 9)
        putRichText(r.pasteboard)
        r.hotkey.press()
        #expect(r.pasteboard.data(forType: .rtf) == nil)
        #expect(await eventually { r.sent.value == 1 })
    }

    @Test func aStoppedHotkeyIsNotRearmedBySettingsChanges() {
        let r = rig()
        r.model.start()
        r.model.stop()
        r.defaults.defaults.set("option+command+v", forKey: "pastePlainShortcut")
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
        #expect(r.hotkey.registered == nil)
    }

    @Test func takenShortcutIsRetriedOnTheNextStart() {
        let r = rig()
        r.hotkey.accept = false
        r.model.start()
        #expect(r.hotkey.registered == nil)
        r.hotkey.accept = true
        r.model.start()                         // permission grant or any registry restart
        #expect(r.hotkey.registered?.keyCode == 9)
    }

    @Test func startTwiceDoesNotRegisterTwice() {
        let r = rig()
        r.model.start()
        r.model.start()
        #expect(r.hotkey.registerCalls.count == 1)
    }

    @Test func withoutAccessibilityTheTextIsPlainButNothingIsSent() async {
        let r = rig(trusted: false)
        r.model.start()
        putRichText(r.pasteboard)
        r.hotkey.press()
        #expect(r.pasteboard.string(forType: .string) == "Bonjour le monde")
        #expect(r.pasteboard.data(forType: .rtf) == nil)
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(r.sent.value == 0)
    }
}
