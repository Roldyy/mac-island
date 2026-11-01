import AppKit
import Testing
@testable import ClipboardFeature

/// The persisted paste log carries steps and counts, never a pasteboard type identifier: a type such as
/// `org.nspasteboard.ConcealedType` tells a reader that a password was copied.
@Suite @MainActor struct PasteLogTests {
    @Test func theConversionLineHoldsCountsOnly() {
        let line = PlainPasteHotkeyService.conversionLogLine(before: 4, after: 2)
        #expect(line == "pasteboard converted: 4 types -> 2 types")
        for identifier in ["org.nspasteboard.ConcealedType", "public.utf8-plain-text", "public.html", "com."] {
            #expect(!line.contains(identifier))
        }
    }

    @Test func aPasteboardWithAConcealedMarkerStillConvertsAndItsIdentifierIsNotInTheLine() {
        let pb = makePasteboard()
        pb.clearContents()
        pb.setString("pa\u{00A0}ss", forType: .string)
        pb.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        let before = pb.types?.count ?? 0
        let outcome = PlainPasteHotkeyService.performPlainPaste(pasteboard: pb, accessibilityTrusted: { false },
                                                                sendPaste: { .posted })
        #expect(outcome == .copiedOnly)
        let line = PlainPasteHotkeyService.conversionLogLine(before: before, after: pb.types?.count ?? 0)
        #expect(!line.contains("Concealed") && !line.contains("org."))
    }

    @Test func theServiceNeverFeedsTypeIdentifiersToTheLogger() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/Features/Clipboard/PlainPasteHotkeyService.swift"),
                              encoding: .utf8)
        let code = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        let loggerLines = code.filter { $0.contains("PasteLog.logger") }
        #expect(!loggerLines.isEmpty)
        for line in loggerLines {
            #expect(!line.contains(".joined("), "a joined list of identifiers reached the log: \(line)")
            #expect(!line.contains("rawValue"), "a type identifier reached the log: \(line)")
        }
        #expect(!code.contains { $0.contains("types \\(") }, "the old line is back")
    }
}
