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
