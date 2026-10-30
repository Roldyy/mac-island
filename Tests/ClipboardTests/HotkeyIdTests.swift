import Carbon.HIToolbox
import Testing
@testable import ClipboardFeature

@Suite struct HotkeyIdTests {
    @Test func acceptsOnlyOurSignatureAndId() {
        let ours = EventHotKeyID(signature: PlainPasteHotkeyService.signature, id: PlainPasteHotkeyService.hotKeyID)
        #expect(PlainPasteHotkeyService.isOurHotKey(ours))
        #expect(!PlainPasteHotkeyService.isOurHotKey(EventHotKeyID(signature: 0x1234_5678, id: PlainPasteHotkeyService.hotKeyID)))
        #expect(!PlainPasteHotkeyService.isOurHotKey(EventHotKeyID(signature: PlainPasteHotkeyService.signature, id: 99)))
    }
}
