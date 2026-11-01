import AppKit
import Foundation
import Testing
@testable import ClipboardFeature

/// One writer for `Scratchpad.json`: while the ported Scratchpad runs, the Clipboard tab's pane is read-only.
@Suite @MainActor struct ScratchpadOwnershipTests {
    private final class Flag { var ported = false }

    private func model(directory: URL, flag: Flag) -> (ClipboardModel, TempDefaults) {
        let td = TempDefaults()
        let model = ClipboardModel(dataDirectory: directory, pasteboard: makePasteboard(),
                                   settings: { ClipboardSettings(defaults: td.defaults) },
                                   accessibilityTrusted: { true }, postAccess: { true },
                                   sendPaste: { .posted }, notify: { _ in }, hotkey: FakeHotkey(),
                                   stopCenter: NotificationCenter(),
                                   portedScratchpadRunning: { flag.ported })
        return (model, td)
    }

    private func seeded() throws -> (URL, URL) {
        let dir = makeTempDir()
        let file = dir.appendingPathComponent("Scratchpad.json")
        try #"{"pads":[{"id":"A","name":"a","text":"ours"}],"selectedID":"A"}"#.write(to: file, atomically: true, encoding: .utf8)
        return (dir, file)
    }

    @Test func theDefaultSaysTheScratchpadIsOurs() {
        #expect(ClipboardFeature.portedScratchpadRunning() == false)
    }

    @Test func whileThePortedScratchpadRunsOurPaneNeitherEditsNorWrites() throws {
        let (dir, file) = try seeded()
        let flag = Flag()
        let (model, td) = model(directory: dir, flag: flag)
        defer { _ = td }
        model.start()
        defer { model.stop() }
        let before = try Data(contentsOf: file)

        flag.ported = true
        #expect(model.scratchpadReadOnly)
        model.padText = "typed into a stale copy"
        model.addPad()
        model.removeSelectedPad()
        model.saveScratch()
        #expect(model.padText == "ours" && model.pads.count == 1, "nothing changed in memory")
        #expect(try Data(contentsOf: file) == before, "nothing was written")

        flag.ported = false
        #expect(!model.scratchpadReadOnly)
        model.addPad()
        #expect(model.pads.count == 2, "back to ours when the ported feature stops")
        #expect(try String(contentsOf: file, encoding: .utf8).contains("Note 2"))
    }

    @Test func aFileRewrittenByTheOtherWriterIsReloadedNotOverwritten() throws {
        let (dir, file) = try seeded()
        let flag = Flag()
        let (model, td) = model(directory: dir, flag: flag)
        defer { _ = td }
        model.start()
        defer { model.stop() }

        let theirs = #"{"pads":[{"id":"A","name":"a","text":"ported edit"},{"id":"B","name":"b","text":""}],"selectedID":"B"}"#
        try theirs.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: file.path)

        model.addPad()  // our save is refused: the file wins and the pane reloads
        #expect(model.pads.map(\.id) == ["A", "B"])
        #expect(try String(contentsOf: file, encoding: .utf8) == theirs, "the ported edits survived")
    }

    @Test func thePaneReloadsWhatThePortedScratchpadWroteWhileItWasHidden() throws {
        let (dir, file) = try seeded()
        let flag = Flag()
        let (model, td) = model(directory: dir, flag: flag)
        defer { _ = td }
        model.start()
        defer { model.stop() }
        try #"{"pads":[{"id":"A","name":"a","text":"ported edit"}],"selectedID":"A"}"#
            .write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: file.path)
        model.reloadScratchpadIfChanged()  // what the pane does when it appears
        #expect(model.padText == "ported edit")
    }

    @Test func theAppDelegateLendsTheRegistryVerdictToTheTab() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/MacIsland/AppDelegate.swift"), encoding: .utf8)
        #expect(source.contains("ClipboardFeature.portedScratchpadRunning = {"))
        #expect(source.contains("registry.isEnabled(\"scratchpad\")"))
    }
}
