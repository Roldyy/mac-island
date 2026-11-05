import AppKit
import Testing
@testable import ClipboardFeature

@Suite @MainActor struct PasteboardWatcherTests {
    func make() -> (PasteboardWatcher, NSPasteboard, TempDefaults, Box) {
        let pb = makePasteboard()
        let td = TempDefaults()
        let w = PasteboardWatcher(pasteboard: pb)
        w.settings = { ClipboardSettings(defaults: td.defaults) }
        w.frontmostBundleID = { "com.example.app" }
        let box = Box()
        w.onChange = { _, capture, _ in box.captures.append(capture) }
        return (w, pb, td, box)
    }
    final class Box { var captures: [PasteboardCapture?] = [] }

    @Test func capturesPlainText() async {
        let (w, pb, td, box) = make(); defer { _ = td }
        pb.clearContents(); pb.setString("hello", forType: .string)
        w.poll()
        #expect(await eventually { box.captures.count == 1 })
        #expect(box.captures == [.text("hello")])
    }

    @Test func dropsCaptureWhenPasteboardChangedMidRead() async {
        let (w, pb, td, box) = make(); defer { _ = td }
        pb.clearContents(); pb.setString("hello", forType: .string)
        w.afterCaptureRead = {
            pb.clearContents(); pb.setString("other", forType: .string)
        }
        w.poll()
        #expect(await eventually { box.captures.count == 1 })
        #expect(box.captures[0] == nil)
    }

    @Test func dropsCaptureWhenItemBecameConcealed() async {
        let (w, pb, td, box) = make(); defer { _ = td }
        pb.clearContents(); pb.setString("hello", forType: .string)
        w.afterCaptureRead = {
            pb.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))   // same item, new type
        }
        w.poll()
        #expect(await eventually { box.captures.count == 1 })
        #expect(box.captures == [nil])
    }

    /// Lane order H (hub count read), R (our own write + count), L (the look): the look belongs to a state older than
    /// the write the model adopted meanwhile, so it must report nothing (it would re-arm auto-clear on the old count).
    @Test func lookOvertakenByOwnWriteReportsNothing() async {
        let (w, pb, td, box) = make(); defer { _ = td }
        pb.clearContents(); pb.setString("older", forType: .string)
        let older = pb.changeCount
        w.poll(changeCount: older)                      // the look is queued on the lane
        w.syncToCurrent(count: older + 1)               // the app's own write, adopted before the look answers
        #expect(await eventually { w.isIdle })
        #expect(box.captures.isEmpty)
        #expect(w.lastChangeCount == older + 1)
    }

    /// The count of an auto-clear is adopted exactly: a copy made after the clear is a change, not the app's own write.
    @Test func copyAfterClearCountIsRecorded() async {
        let (w, pb, td, box) = make(); defer { _ = td }
        pb.clearContents(); pb.setString("secret", forType: .string)
        let clearCount = pb.changeCount                 // what the clear block read, in its own lane block
        pb.clearContents(); pb.setString("copied between", forType: .string)   // lands before the adoption
        w.syncToCurrent(count: clearCount)
        w.poll()
        #expect(await eventually { box.captures.count == 1 })
        #expect(box.captures == [.text("copied between")])
    }
}
