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

    @Test func capturesPlainText() {
        let (w, pb, td, box) = make(); defer { _ = td }
        pb.clearContents(); pb.setString("hello", forType: .string)
        w.poll()
        #expect(box.captures == [.text("hello")])
    }

    @Test func dropsCaptureWhenPasteboardChangedMidRead() {
        let (w, pb, td, box) = make(); defer { _ = td }
        pb.clearContents(); pb.setString("hello", forType: .string)
        w.afterCaptureRead = {
            pb.clearContents(); pb.setString("other", forType: .string)
        }
        w.poll()
        #expect(box.captures.count == 1)
        #expect(box.captures[0] == nil)
    }

    @Test func dropsCaptureWhenItemBecameConcealed() {
        let (w, pb, td, box) = make(); defer { _ = td }
        pb.clearContents(); pb.setString("hello", forType: .string)
        w.afterCaptureRead = {
            pb.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))   // same item, new type
        }
        w.poll()
        #expect(box.captures == [nil])
    }
}
