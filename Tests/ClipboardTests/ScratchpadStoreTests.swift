import Foundation
import Testing
@testable import ClipboardFeature

@Suite struct ScratchpadStoreTests {
    @Test func startsWithOnePad() {
        let s = ScratchpadStore(directory: makeTempDir())
        s.load()
        #expect(s.pads.count == 1)
        #expect(s.selectedID == s.pads[0].id)
    }

    // Observed legacy shape: {"pads":[{"id","name","text"}],"selectedID":"..."}. Synthetic values.
    @Test func readsLegacyShapeTolerantly() throws {
        let dir = makeTempDir()
        let json = """
        {"pads":[{"id":"P1","name":"First","text":"synthetic","extra":true},
                 {"name":"no id","text":"x"},
                 {"id":"P3"},
                 7],
         "selectedID":"P3","futureKey":1}
        """
        try json.write(to: dir.appendingPathComponent("Scratchpad.json"), atomically: true, encoding: .utf8)
        let s = ScratchpadStore(directory: dir)
        s.load()
        #expect(s.pads.count == 3)
        #expect(s.pads[0].text == "synthetic")
        #expect(s.pads[2].id == "P3" && s.pads[2].text == "")
        #expect(s.selectedID == "P3")
    }

    @Test func unknownSelectedFallsBackToFirst() throws {
        let dir = makeTempDir()
        try #"{"pads":[{"id":"A","name":"a","text":""}],"selectedID":"ZZZ"}"#
            .write(to: dir.appendingPathComponent("Scratchpad.json"), atomically: true, encoding: .utf8)
        let s = ScratchpadStore(directory: dir)
        s.load()
        #expect(s.selectedID == "A")
    }

    @Test func editSavePersistsReadable() throws {
        let dir = makeTempDir()
        let a = ScratchpadStore(directory: dir)
        a.load()
        a.updateText("synthetic body", for: a.pads[0].id)
        a.addPad(named: "Second")
        a.save()
        let b = ScratchpadStore(directory: dir)
        b.load()
        #expect(b.pads.map(\.name).contains("Second"))
        #expect(b.pads.first?.text == "synthetic body")
        #expect(b.selectedID == a.selectedID)
        #expect(posix(dir.appendingPathComponent("Scratchpad.json")) == 0o600)
    }

    /// The ported Scratchpad writes this very file. A rewrite from our stale copy would drop its edits.
    @Test func aSaveOverAFileThatChangedOnDiskIsRefused() throws {
        let dir = makeTempDir()
        let file = dir.appendingPathComponent("Scratchpad.json")
        try #"{"pads":[{"id":"A","name":"a","text":"ours"}],"selectedID":"A"}"#.write(to: file, atomically: true, encoding: .utf8)
        let s = ScratchpadStore(directory: dir)
        s.load()
        // The other writer: two pads, newer mtime.
        let theirs = #"{"pads":[{"id":"A","name":"a","text":"ported edit"},{"id":"B","name":"b","text":"new"}],"selectedID":"B"}"#
        try theirs.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: file.path)
        s.updateText("stale local edit", for: "A")
        #expect(s.changedOnDisk)
        #expect(s.save() == false, "refused")
        #expect(try String(contentsOf: file, encoding: .utf8) == theirs, "the ported edits are still on disk")
        // Reloading takes theirs; the next save goes through.
        s.load()
        #expect(s.pads.map(\.id) == ["A", "B"] && s.pads[0].text == "ported edit")
        #expect(!s.changedOnDisk)
        s.updateText("after reload", for: "B")
        #expect(s.save())
        #expect(try String(contentsOf: file, encoding: .utf8).contains("after reload"))
    }

    @Test func consecutiveOwnSavesAreNotMistakenForAnotherWriter() {
        let s = ScratchpadStore(directory: makeTempDir())
        s.load()
        s.updateText("one", for: s.pads[0].id)
        #expect(s.save())
        s.updateText("two", for: s.pads[0].id)
        #expect(s.save(), "the stamp follows our own write")
        #expect(!s.changedOnDisk)
    }

    @Test func removeKeepsAtLeastOnePad() {
        let s = ScratchpadStore(directory: makeTempDir())
        s.load()
        s.removePad(id: s.pads[0].id)
        #expect(s.pads.count == 1)
        s.addPad(named: "B")
        s.removePad(id: s.selectedID)
        #expect(s.pads.count == 1)
        #expect(s.pads.contains { $0.id == s.selectedID })
    }
}
