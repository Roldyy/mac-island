import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import PortKit

/// Lane W5B: the drop logic of the island's Étagère tab (a drop on a non-activating panel at `.screenSaver` level goes
/// through SwiftUI's `onDrop`, which is what already works there), driven with fakes: no real pasteboard, no panel, no
/// `ShelfService`. The waits have no millisecond budget: each answer is a continuation that the code resumes itself.
@MainActor
@Suite(.serialized) struct ShelfDropTests {
    struct FakeProvider: ShelfDropProviding {
        var url: URL?
        var carries = true
        /// Answers from another thread, after a pause that depends on `lag`, so the order of answers differs from the
        /// order of the providers.
        var lag: UInt32 = 0
        let loads: Box<Int>

        var carriesFileURL: Bool { carries }

        func loadFileURL(_ done: @escaping @Sendable (URL?) -> Void) {
            loads.value += 1
            let url = url
            if lag == 0 {
                done(url)
            } else {
                DispatchQueue.global().async {
                    usleep(lag)
                    done(url)
                }
            }
        }
    }

    @MainActor final class FakeSink: ShelfDropSink {
        var accepts = true
        var accepted = true
        var batches: [[URL]] = []
        var acceptsDrops: Bool { accepts }
        func add(_ urls: [URL]) -> Bool {
            batches.append(urls)
            return accepted
        }
    }

    /// `accepted` is the immediate answer to the drag; `added` the number of files that reached the sink (nil when the
    /// drop was refused and nothing could follow).
    func drop(_ providers: [FakeProvider], into sink: FakeSink) async -> (accepted: Bool, added: Int?) {
        var accepted = false
        let added: Int? = await withCheckedContinuation { continuation in
            accepted = ShelfIslandDrop.handle(providers, into: sink) { continuation.resume(returning: $0) }
            if !accepted { continuation.resume(returning: nil) }
        }
        return (accepted, added)
    }

    func file(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/w5b-drop/\(name)") }

    @Test func aFileDropIsAcceptedAndLandsOnTheShelfAsOneBatch() async {
        let loads = Box(0)
        let sink = FakeSink()
        let result = await drop([FakeProvider(url: file("a.txt"), loads: loads),
                                 FakeProvider(url: file("b.txt"), loads: loads)], into: sink)
        #expect(result.accepted && result.added == 2)
        #expect(sink.batches == [[file("a.txt"), file("b.txt")]], "several files of one drop are one batch, in drag order")
    }

    @Test func theFilesKeepTheirDragOrderWhateverOrderTheyAreReadIn() async {
        let loads = Box(0)
        let sink = FakeSink()
        let providers = [FakeProvider(url: file("1"), lag: 40_000, loads: loads),
                         FakeProvider(url: file("2"), lag: 5_000, loads: loads),
                         FakeProvider(url: file("3"), lag: 0, loads: loads)]
        let result = await drop(providers, into: sink)
        #expect(result.added == 3)
        #expect(sink.batches == [[file("1"), file("2"), file("3")]])
    }

    @Test func aDropWhileTheShelfIsOffIsRefusedAndNothingIsRead() async {
        let loads = Box(0)
        let sink = FakeSink()
        sink.accepts = false
        let result = await drop([FakeProvider(url: file("a.txt"), loads: loads)], into: sink)
        #expect(result.accepted == false && result.added == nil)
        #expect(loads.value == 0, "a refused drop never reads the dragged items")
        #expect(sink.batches.isEmpty)
    }

    @Test func textOrLinksWithoutAFileAreNotTakenByTheIslandTab() async {
        let loads = Box(0)
        let sink = FakeSink()
        let result = await drop([FakeProvider(url: nil, carries: false, loads: loads)], into: sink)
        #expect(result.accepted == false)
        #expect(loads.value == 0 && sink.batches.isEmpty)
    }

    @Test func anItemThatGivesNoURLIsSkippedAndTheOthersStillLand() async {
        let loads = Box(0)
        let sink = FakeSink()
        let result = await drop([FakeProvider(url: nil, loads: loads), FakeProvider(url: file("ok.txt"), loads: loads)],
                                into: sink)
        #expect(result.accepted && result.added == 1)
        #expect(sink.batches == [[file("ok.txt")]])
    }

    @Test func ifNoItemGivesAURLNothingIsAddedAndTheCountIsZero() async {
        let loads = Box(0)
        let sink = FakeSink()
        let result = await drop([FakeProvider(url: nil, loads: loads)], into: sink)
        #expect(result.accepted && result.added == 0)
        #expect(sink.batches.isEmpty)
    }

    @Test func aSinkThatRefusesTheFilesReportsZero() async {
        let loads = Box(0)
        let sink = FakeSink()
        sink.accepted = false
        let result = await drop([FakeProvider(url: file("full.txt"), loads: loads)], into: sink)
        #expect(result.accepted && result.added == 0, "the shelf is full: the drag was taken, nothing was added")
    }

    // MARK: Decoding what the pasteboard hands over

    @Test func onlyFileURLsAreDecoded() {
        let url = file("x.txt")
        #expect(ShelfIslandDrop.fileURL(from: url.dataRepresentation as NSData) == url, "data form (the usual one)")
        #expect(ShelfIslandDrop.fileURL(from: url as NSURL) == url)
        #expect(ShelfIslandDrop.fileURL(from: NSURL(string: "https://example.com/a")!) == nil, "a web link is not a file")
        #expect(ShelfIslandDrop.fileURL(from: "/tmp/x" as NSString) == nil)
        #expect(ShelfIslandDrop.fileURL(from: nil) == nil)
        #expect(ShelfIslandDrop.acceptedTypes == [UTType.fileURL])
    }

    @Test func theLiveProviderAdapterReadsAFileURLFromARealItemProvider() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("w5b-provider-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let provider = ShelfItemProvider(provider: NSItemProvider(object: url as NSURL))
        #expect(provider.carriesFileURL)
        let read: URL? = await withCheckedContinuation { continuation in
            provider.loadFileURL { continuation.resume(returning: $0) }
        }
        #expect(read?.resolvingSymlinksInPath() == url.resolvingSymlinksInPath())
        let text = ShelfItemProvider(provider: NSItemProvider(object: "just text" as NSString))
        #expect(text.carriesFileURL == false)
    }
}
