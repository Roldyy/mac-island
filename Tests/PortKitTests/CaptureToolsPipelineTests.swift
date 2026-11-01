import AppKit
import CoreImage
import Foundation
import Testing
@testable import PortKit

/// The OCR text pipeline, the QR safety and the colour formats, on images the tests draw themselves. Vision runs
/// on those bundled-by-construction fixtures (offline, no screen, no capture); nothing touches the pasteboard, the
/// camera, the screen or the network.
@MainActor
@Suite(.serialized) struct CaptureToolsPipelineTests {
    // MARK: Fixtures

    private static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    private static func context(width: Int, height: Int) -> CGContext {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx
    }

    /// Black text on white, big enough for the fast model too.
    static func textImage(_ lines: [String]) -> CGImage {
        let width = 1100
        let height = 40 + lines.count * 130
        let ctx = context(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for (index, line) in lines.enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 78, weight: .semibold), .foregroundColor: NSColor.black,
            ]
            let y = CGFloat(height - 40 - (index + 1) * 120)
            NSAttributedString(string: line, attributes: attributes).draw(at: CGPoint(x: 40, y: y))
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    /// A QR code with a wide quiet zone, drawn at 12 px per module with no interpolation.
    static func qrImage(_ payload: String) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let code = CIContext(options: [.useSoftwareRenderer: true])
            .createCGImage(scaled, from: scaled.extent) else { return nil }
        let pad = 120
        let ctx = context(width: code.width + 2 * pad, height: code.height + 2 * pad)
        ctx.interpolationQuality = .none
        ctx.draw(code, in: CGRect(x: pad, y: pad, width: code.width, height: code.height))
        return ctx.makeImage()
    }

    // MARK: OCR

    @Test func aDrawnSentenceComesBackAsTextWithItsLinesInReadingOrder() {
        let image = Self.textImage(["Mac Island", "Capture 2026"])
        guard case .text(let text) = ScreenTextService.outcome(for: image, detectQRCodes: false, removeLineBreaks: false) else {
            Issue.record("expected recognized text")
            return
        }
        let lower = text.lowercased()
        #expect(lower.contains("island") && lower.contains("capture"), "\(text)")
        #expect(text.contains("\n"), "two lines stay two lines")
        let island = lower.range(of: "island")!.lowerBound
        let capture = lower.range(of: "capture")!.lowerBound
        #expect(island < capture, "top line first")
    }

    @Test func removingLineBreaksJoinsTheLinesIntoOneParagraph() {
        let image = Self.textImage(["Mac Island", "Capture 2026"])
        guard case .text(let text) = ScreenTextService.outcome(for: image, detectQRCodes: false, removeLineBreaks: true) else {
            Issue.record("expected recognized text")
            return
        }
        #expect(!text.contains("\n"), "\(text)")
        #expect(text.lowercased().contains("island") && text.lowercased().contains("capture"))
    }

    @Test func aBlankImageIsEmptyNotAnError() {
        let blank = Self.context(width: 600, height: 300).makeImage()!
        #expect(ScreenTextService.outcome(for: blank, detectQRCodes: true, removeLineBreaks: false) == .empty)
    }

    @Test func recognizedLinesJoinInReadingOrderWithOrWithoutBreaks() {
        typealias Line = QuickToolsSupport.RecognizedLine
        let lines = [Line(text: "second", x: 0.1, y: 0.4), Line(text: "first", x: 0.1, y: 0.8),
                     Line(text: "  ", x: 0.1, y: 0.6), Line(text: "third", x: 0.1, y: 0.1)]
        #expect(QuickToolsSupport.joinedRecognizedText(lines, removingLineBreaks: false) == "first\nsecond\nthird")
        #expect(QuickToolsSupport.joinedRecognizedText(lines, removingLineBreaks: true) == "first second third")
    }

    // MARK: QR

    @Test func aQRCodeIsReadAndItsLinkIsOpenableOnlyAsAWebAddress() throws {
        let payload = "https://example.com/mac-island?x=1"
        let image = try #require(Self.qrImage(payload), "CoreImage cannot draw a QR here")
        guard case .qr(let reading) = ScreenTextService.outcome(for: image, detectQRCodes: true, removeLineBreaks: false) else {
            Issue.record("expected a QR reading")
            return
        }
        #expect(reading.payload == payload, "the decoded text is what the panel shows first")
        #expect(reading.url == URL(string: payload))
    }

    @Test func aQRTextThatIsNotAWebLinkHasNoOpenAction() throws {
        let image = try #require(Self.qrImage("Wi-Fi mot de passe 12345"), "CoreImage cannot draw a QR here")
        guard case .qr(let reading) = ScreenTextService.outcome(for: image, detectQRCodes: true, removeLineBreaks: false) else {
            Issue.record("expected a QR reading")
            return
        }
        #expect(reading.payload == "Wi-Fi mot de passe 12345" && reading.url == nil)
    }

    @Test func onlyPlainHttpAndHttpsLinksCanBeOpenedAScannedCodeNeverLaunchesAnotherScheme() {
        for ok in ["https://example.com", "http://example.com/a?b=c", "  https://example.com/x  "] {
            #expect(QuickToolsSupport.openableURL(from: ok) != nil, "\(ok)")
        }
        for refused in ["file:///etc/passwd", "javascript:alert(1)", "mailto:a@b.c", "tel:+3212345", "ssh://host",
                        "x-apple.systempreferences:com.apple.preference.security", "data:text/html,hi", "https://",
                        "https://example.com/a b", "example.com", "", "   ", "macisland://quit", "smb://share/x"] {
            #expect(QuickToolsSupport.openableURL(from: refused) == nil, "\(refused)")
        }
    }

    @Test func severalCodesNeverOfferAnOpenAction() {
        let codes = [QuickToolsSupport.DecodedBarcode(payload: "https://a.example", x: 0.1, y: 0.9),
                     QuickToolsSupport.DecodedBarcode(payload: "https://b.example", x: 0.6, y: 0.9)]
        #expect(QuickToolsSupport.joinedBarcodePayloads(codes) == "https://a.example\nhttps://b.example")
        let payload = QuickToolsSupport.joinedBarcodePayloads(codes)
        #expect(QuickToolsSupport.openableURL(from: payload) == nil, "two lines are not one address")
    }

    // MARK: Colour formats

    @Test func theFourCopyFormatsOfAKnownColour() {
        func text(_ format: ColorCopyFormat, bare: Bool = false) -> String {
            ColorValue.string(red: 1, green: 0.5, blue: 0, format: format, bareHex: bare)
        }
        #expect(text(.hex) == "#FF8000")
        #expect(text(.hex, bare: true) == "FF8000")
        #expect(text(.rgb) == "rgb(255, 128, 0)")
        #expect(text(.hsl) == "hsl(30, 100%, 50%)")
        #expect(text(.swiftui) == "Color(red: 1.000, green: 0.500, blue: 0.000)")
        #expect(text(.rgb, bare: true) == "rgb(255, 128, 0)", "the bare switch only touches HEX")
    }

    @Test func outOfRangeSamplesAreClampedAndBlackAndWhiteAreExact() {
        #expect(ColorValue.string(red: 1.7, green: -0.4, blue: 0.2, format: .hex) == "#FF0033")
        #expect(ColorValue.string(red: 0, green: 0, blue: 0, format: .hsl) == "hsl(0, 0%, 0%)")
        #expect(ColorValue.string(red: 1, green: 1, blue: 1, format: .hsl) == "hsl(0, 0%, 100%)")
        #expect(ColorValue.string(red: 1, green: 0, blue: 0, alpha: 0.5, format: .hex) == "#FF000080")
        #expect(ColorCopyFormat.sanitized("nonsense") == .hex)
        #expect(ColorCopyFormat.allCases.map(\.label) == ["HEX", "RGB", "HSL", "SwiftUI"])
    }

    @Test func theSamplerFormatsWithTheChosenFormatFromTheHostDefaultsWithoutTouchingThePasteboard() {
        PortHostFixture.isolated { defaults in
            let color = NSColor(srgbRed: 0, green: 0.5, blue: 1, alpha: 1)
            let before = NSPasteboard.general.changeCount
            #expect(ColorSamplerService.shared.formattedValue(color) == "#0080FF", "hex by default")
            defaults.set("rgb", forKey: DefaultsKey.colorPickerFormat)
            #expect(ColorSamplerService.shared.formattedValue(color) == "rgb(0, 128, 255)")
            defaults.set("hex", forKey: DefaultsKey.colorPickerFormat)
            defaults.set(true, forKey: DefaultsKey.colorPickerBareHex)
            #expect(ColorSamplerService.shared.formattedValue(color) == "0080FF")
            defaults.set("garbage", forKey: DefaultsKey.colorPickerFormat)
            #expect(ColorSamplerService.shared.formattedValue(color) == "0080FF", "an unknown stored format falls back to HEX")
            #expect(NSPasteboard.general.changeCount == before, "formatting alone never copies")
        }
    }
}
