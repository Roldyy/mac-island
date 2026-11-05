import Foundation
import Testing
@testable import ClipboardFeature

struct FakeNode: PasteMenuNode {
    var title = ""
    var cmdChar: String?
    var cmdModifiers: Int?
    var enabled = true
    var kids: [FakeNode] = []
    func children() -> [FakeNode] { kids }
}

@Suite struct PasteMenuFinderTests {
    func paste(_ title: String = "Paste", mods: Int? = 0, enabled: Bool = true, char: String? = "V") -> FakeNode {
        FakeNode(title: title, cmdChar: char, cmdModifiers: mods, enabled: enabled)
    }
    func bar(_ items: [FakeNode]) -> [FakeNode] {
        [FakeNode(title: "File", kids: [FakeNode(title: "New", cmdChar: "N", cmdModifiers: 0)]),
         FakeNode(title: "Edit", kids: items)]
    }
    func title(_ f: PasteMenuInvoker.Found<FakeNode>) -> String? {
        if case .item(let n) = f { return n.title }
        return nil
    }

    @Test func findsTheCommandOnlyPasteItem() {
        #expect(title(PasteMenuInvoker.find(in: bar([paste("Copy", char: "C"), paste()]))) == "Paste")
    }

    @Test func skipsStyleFormatMatchAndMoveVariants() {
        let items = [paste("Paste and Match Style", mods: 0), paste("Paste Style", mods: 0),
                     paste("Coller sans mise en forme (Format)", mods: 0), paste("Déplacer l'élément ici", mods: 0)]
        if case .none = PasteMenuInvoker.find(in: bar(items)) {} else { Issue.record("a variant was taken") }
    }

    @Test func skipsItemsWithExtraModifiers() {
        // option+cmd+V = 2, shift+option+cmd+V = 3
        if case .none = PasteMenuInvoker.find(in: bar([paste("Paste", mods: 2), paste("Paste", mods: 3)])) {}
        else { Issue.record("a modified shortcut was taken") }
    }

    @Test func lowercaseCharIsAccepted() {
        #expect(title(PasteMenuInvoker.find(in: bar([paste(char: "v")]))) == "Paste")
    }

    @Test func aDisabledItemIsReportedAsDisabledNotNotFound() {
        if case .disabled = PasteMenuInvoker.find(in: bar([paste(enabled: false)])) {} else { Issue.record("expected disabled") }
    }

    @Test func anEnabledItemBeatsADisabledTwin() {
        #expect(title(PasteMenuInvoker.find(in: bar([paste(enabled: false), paste("Coller")]))) == "Coller")
    }

    @Test func followsASubmenuButNotForever() {
        let deep = FakeNode(title: "More", kids: [FakeNode(title: "Deeper", kids: [FakeNode(title: "Deepest", kids: [paste("Paste")])])])
        if case .none = PasteMenuInvoker.find(in: [deep]) {} else { Issue.record("search went too deep") }
        let shallow = FakeNode(title: "More", kids: [FakeNode(title: "Sub", kids: [paste("Paste")])])
        #expect(title(PasteMenuInvoker.find(in: [shallow])) == "Paste")
    }

    @Test func anExpiredBudgetStopsTheWalk() {
        if case .none = PasteMenuInvoker.find(in: bar([paste()]), expired: { true }) {} else { Issue.record("walk ignored the budget") }
    }
}

@Suite @MainActor struct PasteDispatcherTests {
    final class Rig {
        var pressed: [pid_t] = []
        var keys = 0
        var t = 0
    }
    func dispatcher(_ rig: Rig, front: pid_t?, press: MenuPressResult, keys: PasteSendResult = .posted) -> PasteDispatcher {
        PasteDispatcher(frontPID: { front }, ownPID: 1,
                        pressMenu: { rig.pressed.append($0); rig.t += 5; return press },
                        sendKeys: { rig.keys += 1; rig.t += 300; return keys },
                        nowMs: { rig.t })
    }

    @Test func aMenuPressIsEnoughAndNeverWaitsForKeys() async {
        let rig = Rig()
        #expect(await dispatcher(rig, front: 42, press: .pressed).run() == .posted)
        #expect(rig.pressed == [42])
        #expect(rig.keys == 0)
    }

    @Test(arguments: [MenuPressResult.notFound, .disabled, .error, .timedOut])
    func anyMenuFailureFallsBackToTheKeySequencer(_ result: MenuPressResult) async {
        let rig = Rig()
        #expect(await dispatcher(rig, front: 42, press: result).run() == .posted)
        #expect(rig.keys == 1)
    }

    @Test func theKeyFallbackReportsItsOwnFailure() async {
        let rig = Rig()
        #expect(await dispatcher(rig, front: 42, press: .notFound, keys: .eventFailed).run() == .eventFailed)
    }

    @Test func noFrontAppOrOurselvesGoesStraightToKeys() async {
        let rig = Rig()
        _ = await dispatcher(rig, front: nil, press: .pressed).run()
        _ = await dispatcher(rig, front: 1, press: .pressed).run()
        #expect(rig.pressed.isEmpty)
        #expect(rig.keys == 2)
    }

    @Test func theLogLinesCarryCountsOnly() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/Features/Clipboard/PasteMenuInvoker.swift"), encoding: .utf8)
        let lines = text.split(separator: "\n").filter { $0.contains("PasteLog.logger") }
        #expect(lines.count == 4)
        for l in lines { #expect(!l.contains("title") && !l.contains("pasteboard")) }
    }
}
