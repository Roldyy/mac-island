import AppKit
import Testing
@testable import ClipboardFeature

@Suite @MainActor struct PlainPasteFlowTests {
    static let concealed = "org.nspasteboard.ConcealedType"

    func fixture(delay: Double = 0.25) -> (ClipboardModel, NSPasteboard, TempDefaults) {
        let pb = makePasteboard()
        let td = TempDefaults()
        td.defaults.set(true, forKey: "clipboardAutoClearOnDelay")
        td.defaults.set(delay, forKey: "clipboardAutoClearDelaySeconds")
        let model = ClipboardModel(dataDirectory: makeTempDir(), pasteboard: pb,
                                   settings: { ClipboardSettings(defaults: td.defaults) },
                                   accessibilityTrusted: { false }, sendPaste: {})
        return (model, pb, td)
    }

    @Test func markerSurvivesPlainPaste() {
        let pb = makePasteboard()
        pb.clearContents()
        pb.setString("pa\u{00A0}ss", forType: .string)
        pb.setData(Data(), forType: .init(Self.concealed))
        let outcome = PlainPasteHotkeyService.performPlainPaste(pasteboard: pb, accessibilityTrusted: { false },
                                                                sendPaste: {})
        #expect(outcome == .copiedOnly)
        #expect(pb.string(forType: .string) == "pa ss")
        #expect(pb.types?.contains(.init(Self.concealed)) == true)
    }

    @Test func noMarkerIsAddedWhenThereWasNone() {
        let pb = makePasteboard()
        pb.clearContents(); pb.setString("x", forType: .string)
        _ = PlainPasteHotkeyService.performPlainPaste(pasteboard: pb, accessibilityTrusted: { false }, sendPaste: {})
        #expect(pb.types?.contains(.init(Self.concealed)) != true)
    }

    @Test func emptyPasteboardIsNothingToPaste() {
        let pb = makePasteboard()
        pb.clearContents()
        #expect(PlainPasteHotkeyService.performPlainPaste(pasteboard: pb, accessibilityTrusted: { false },
                                                          sendPaste: {}) == .nothingToPaste)
    }

    @Test func pasteIsSentOnlyWhenTrusted() async throws {
        let pb = makePasteboard()
        pb.clearContents(); pb.setString("x", forType: .string)
        var sent = 0
        let r = PlainPasteHotkeyService.performPlainPaste(pasteboard: pb, accessibilityTrusted: { true },
                                                          sendPaste: { sent += 1 })
        #expect(r == .pasted)
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(sent == 1)
    }

    @Test func modelPlainPasteRearmsAutoClearWithTheNewCount() async throws {
        let (model, pb, td) = fixture()
        defer { _ = td }
        pb.clearContents()
        pb.setString("pa\u{00A0}ss", forType: .string)
        pb.setData(Data(), forType: .init(Self.concealed))
        let before = pb.changeCount
        #expect(model.plainPasteTriggered() == .copiedOnly)
        #expect(pb.changeCount != before)
        #expect(pb.types?.contains(.init(Self.concealed)) == true)
        try await Task.sleep(nanoseconds: 700_000_000)
        #expect(pb.string(forType: .string) == nil)   // re-armed with the new count: wiped
    }

    @Test func copyAfterPlainPasteSurvivesTheOldTimer() async throws {
        let (model, pb, td) = fixture()
        defer { _ = td }
        pb.clearContents(); pb.setString("one", forType: .string)
        _ = model.plainPasteTriggered()
        pb.clearContents(); pb.setString("two", forType: .string)   // newer copy
        try await Task.sleep(nanoseconds: 700_000_000)
        #expect(pb.string(forType: .string) == "two")
    }
}
