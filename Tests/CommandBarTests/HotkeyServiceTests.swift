import Carbon.HIToolbox
import Testing
@testable import CommandBarFeature

@Suite struct HotkeyServiceTests {
    @Test func recognisesOnlyItsOwnSignatureAndId() {
        #expect(CommandBarHotkeyService.isOurHotKey(signature: CommandBarHotkeyService.signature,
                                                    id: CommandBarHotkeyService.hotKeyID))
        // The Clipboard feature's id ('MICL', 1) must be left to its own handler.
        #expect(!CommandBarHotkeyService.isOurHotKey(signature: 0x4D49_434C, id: 1))
        #expect(!CommandBarHotkeyService.isOurHotKey(signature: CommandBarHotkeyService.signature, id: 99))
        #expect(!CommandBarHotkeyService.isOurHotKey(signature: 0, id: 0))
        #expect(CommandBarHotkeyService.signature != 0x4D49_434C)
    }

    @Test func foreignIdsAreNotHandled() {
        #expect(CommandBarHotkeyService.handlerResult(signature: 0x4D49_434C, id: 1) == OSStatus(eventNotHandledErr))
        #expect(CommandBarHotkeyService.handlerResult(signature: CommandBarHotkeyService.signature,
                                                      id: CommandBarHotkeyService.hotKeyID) == noErr)
    }

    @Test func statusMapping() {
        let spec = HotkeySpec.default
        #expect(HotkeyStatus.from(osStatus: noErr, spec: spec) == .active("\u{2325}Space"))
        #expect(HotkeyStatus.from(osStatus: Int32(eventHotKeyExistsErr), spec: spec) == .conflict)
        #expect(HotkeyStatus.from(osStatus: -50, spec: spec) == .failed(-50))
        #expect(HotkeyStatus.conflict.message == "d\u{00E9}j\u{00E0} utilis\u{00E9}")
        #expect(HotkeyStatus.off.message.isEmpty == false)
    }
}

@Suite struct PanelGeometryTests {
    @Test func centeredNearTopAndOnScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let f = PanelGeometry.frame(in: screen)
        #expect(f.midX == screen.midX)
        #expect(f.maxY < screen.maxY && f.maxY > screen.midY)
        #expect(screen.contains(f))
    }

    @Test func smallScreenAndOffsetOrigin() {
        let screen = CGRect(x: -1440, y: 200, width: 500, height: 300)
        let f = PanelGeometry.frame(in: screen)
        #expect(f.width == 500 && f.height == 300)
        #expect(screen.contains(f))
    }
}
