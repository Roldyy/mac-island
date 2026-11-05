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
                                   accessibilityTrusted: { false }, sendPaste: { .posted }, notify: { _ in })
        return (model, pb, td)
    }

    @Test func markerSurvivesPlainPaste() async {
        let pb = makePasteboard()
        pb.clearContents()
        pb.setString("pa\u{00A0}ss", forType: .string)
        pb.setData(Data(), forType: .init(Self.concealed))
        let outcome = await plainPaste(pb)
        #expect(outcome == .copiedOnly)
        #expect(pb.string(forType: .string) == "pa ss")
        #expect(pb.types?.contains(.init(Self.concealed)) == true)
    }

    @Test func noMarkerIsAddedWhenThereWasNone() async {
        let pb = makePasteboard()
        pb.clearContents(); pb.setString("x", forType: .string)
        _ = await plainPaste(pb)
        #expect(pb.types?.contains(.init(Self.concealed)) != true)
    }

    @Test func emptyPasteboardIsNothingToPaste() async {
        let pb = makePasteboard()
        pb.clearContents()
        #expect(await plainPaste(pb) == .nothingToPaste)
    }

    @Test func pasteIsSentOnlyWhenTrusted() async throws {
        let pb = makePasteboard()
        pb.clearContents(); pb.setString("x", forType: .string)
        var sent = 0
        let r = await plainPaste(pb, accessibilityTrusted: { true }, sendPaste: { sent += 1; return .posted })
        #expect(r == .pasted)
        #expect(await eventually { sent == 1 })
    }

    // MARK: - Why the paste used to vanish: ordering, permissions, notices, history

    @Test func plainTextIsOnThePasteboardBeforeThePostAndTheCountIsStable() async throws {
        let pb = makePasteboard()
        pb.clearContents(); pb.setString("pa\u{00A0}ss", forType: .string)
        pb.setData(Data("{\\rtf1 x}".utf8), forType: .rtf)
        var seenAtSend: (String?, Bool, Int)?
        var afterWriteCount: Int?
        var sentBeforeCompletion = true
        var r: PlainPasteOutcome?
        PlainPasteHotkeyService.performPlainPaste(
            pasteboard: pb, accessibilityTrusted: { true }, postAccess: { true },
            sendPaste: { seenAtSend = (pb.string(forType: .string), pb.data(forType: .rtf) == nil, pb.changeCount); return .posted },
            afterWrite: { _ in afterWriteCount = pb.changeCount }) { outcome in
                sentBeforeCompletion = seenAtSend != nil
                r = outcome
            }
        #expect(await eventually { r != nil })
        #expect(r == .pasted)
        #expect(!sentBeforeCompletion)                   // never inline: it waits for the modifiers on a task
        #expect(await eventually { seenAtSend != nil })
        #expect(seenAtSend?.0 == "pa ss")
        #expect(seenAtSend?.1 == true)                   // styles gone
        #expect(seenAtSend?.2 == afterWriteCount)        // nothing touched the pasteboard in between
    }

    @Test func missingPostAccessPostsNothingAndKeepsTheTextForAManualPaste() async throws {
        let pb = makePasteboard()
        pb.clearContents(); pb.setString("pa\u{00A0}ss", forType: .string)
        var sent = 0
        let r = await plainPaste(
            pb, accessibilityTrusted: { true }, postAccess: { false },
            sendPaste: { sent += 1; return .posted })
        #expect(r == .copiedOnly)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(sent == 0)
        #expect(pb.string(forType: .string) == "pa ss")
    }

    @Test func modelTellsTheUserWhenItCannotPaste() async throws {
        let td = TempDefaults()
        var notices: [PlainPasteNotice] = []
        var sent = 0
        let pb = makePasteboard()
        let model = ClipboardModel(dataDirectory: makeTempDir(), pasteboard: pb,
                                   settings: { ClipboardSettings(defaults: td.defaults) },
                                   accessibilityTrusted: { true }, postAccess: { false },
                                   sendPaste: { sent += 1; return .posted }, notify: { notices.append($0) })
        pb.clearContents(); pb.setString("x", forType: .string)
        #expect(await plainPasteOutcome(model) == .copiedOnly)
        #expect(notices == [.needsPermission])
        pb.clearContents()
        #expect(await plainPasteOutcome(model) == .nothingToPaste)
        #expect(notices == [.needsPermission, .nothingToPaste])
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(sent == 0)
    }

    @Test func eventCreationFailureIsAnnounced() async throws {
        let td = TempDefaults()
        var notices: [PlainPasteNotice] = []
        let pb = makePasteboard()
        let model = ClipboardModel(dataDirectory: makeTempDir(), pasteboard: pb,
                                   settings: { ClipboardSettings(defaults: td.defaults) },
                                   accessibilityTrusted: { true }, postAccess: { true },
                                   sendPaste: { .eventFailed }, notify: { notices.append($0) })
        pb.clearContents(); pb.setString("x", forType: .string)
        #expect(await plainPasteOutcome(model) == .pasted)
        #expect(await eventually { notices == [.eventFailed] })
    }

    @Test func permissionNoticeWordingMatchesShellKit() {
        #expect(PlainPasteNotice.needsPermission.text == "Autorisation requise : Surveillance de l'entrée / Accessibilité")
    }

    @Test func historyDoesNotRecordTheConvertedItemAgain() async throws {
        let td = TempDefaults()
        let pb = makePasteboard()
        let model = ClipboardModel(dataDirectory: makeTempDir(), pasteboard: pb,
                                   settings: { ClipboardSettings(defaults: td.defaults) },
                                   accessibilityTrusted: { true }, postAccess: { true },
                                   sendPaste: { .posted }, notify: { _ in }, hotkey: FakeHotkey())
        model.start()
        defer { model.stop() }
        pb.clearContents(); pb.setString("co\u{00A0}py", forType: .string)
        #expect(await eventually { model.entries.count == 1 })   // the original copy is recorded once
        #expect(await plainPasteOutcome(model) == .pasted)
        let polls = model.watcherPollCount
        #expect(await eventually { model.watcherPollCount >= polls + 3 })   // the loop ticked three more times
        #expect(model.entries.count == 1)
        #expect(model.entries.first?.text == "co\u{00A0}py")     // designed: history keeps the original, not the plain copy
    }

    @Test func modelPlainPasteRearmsAutoClearWithTheNewCount() async throws {
        let (model, pb, td) = fixture()
        defer { _ = td }
        pb.clearContents()
        pb.setString("pa\u{00A0}ss", forType: .string)
        pb.setData(Data(), forType: .init(Self.concealed))
        let before = pb.changeCount
        #expect(await plainPasteOutcome(model) == .copiedOnly)
        #expect(pb.changeCount != before)
        #expect(pb.types?.contains(.init(Self.concealed)) == true)
        var wiped = false
        for _ in 0..<400 where !wiped {
            wiped = await onLane { pb.string(forType: .string) } == nil
            if !wiped { try? await Task.sleep(for: .milliseconds(10)) }
        }
        #expect(wiped, "re-armed with the new count: wiped")
    }

    @Test func copyAfterPlainPasteSurvivesTheOldTimer() async throws {
        let (model, pb, td) = fixture()
        defer { _ = td }
        pb.clearContents(); pb.setString("one", forType: .string)
        _ = await plainPasteOutcome(model)
        pb.clearContents(); pb.setString("two", forType: .string)   // newer copy
        try await Task.sleep(nanoseconds: 700_000_000)
        #expect(pb.string(forType: .string) == "two")
    }
}
