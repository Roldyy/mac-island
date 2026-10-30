import AppKit
import Foundation
import Testing
@testable import FinderFeature

@Suite struct ImagePasteTests {
    let fs = SystemFileInspector()
    // 2026-10-30 14:03:22 UTC
    let date = Date(timeIntervalSince1970: 1_793_369_002)

    func tiff() -> Data {
        let img = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { r in
            NSColor.red.setFill(); r.fill(); return true
        }
        return img.tiffRepresentation!
    }

    @Test func fileNameIsTimestamped() {
        let name = ImagePaste.fileName(date: date, timeZone: TimeZone(identifier: "UTC")!)
        #expect(name == "Image 2026-10-30 at 14.03.22.png")
    }
    @Test func convertsTiffToPNG() throws {
        let png = try #require(ImagePaste.pngData(png: nil, tiff: tiff()))
        #expect(png.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
    }
    @Test func keepsExistingPNGAndRejectsGarbage() throws {
        let png = try #require(ImagePaste.pngData(png: nil, tiff: tiff()))
        #expect(ImagePaste.pngData(png: png, tiff: nil) == png)
        #expect(ImagePaste.pngData(png: Data("nope".utf8), tiff: nil) == nil)
        #expect(ImagePaste.pngData(png: nil, tiff: nil) == nil)
    }
    @Test func savesWithoutOverwriting() throws {
        let dir = mkdir(makeTempDir().appendingPathComponent("d"))
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        try ImagePaste.save(png: png, in: dir, date: date, timeZone: TimeZone(identifier: "UTC")!, inspector: fs)
        try ImagePaste.save(png: png, in: dir, date: date, timeZone: TimeZone(identifier: "UTC")!, inspector: fs)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names == ["Image 2026-10-30 at 14.03.22 2.png", "Image 2026-10-30 at 14.03.22.png"])
    }
    @Test func refusesMissingFolder() {
        let dir = makeTempDir().appendingPathComponent("gone")
        #expect(throws: MoveRefusal.destinationUnavailable) {
            try ImagePaste.save(png: Data([1]), in: dir, date: date, timeZone: .gmt, inspector: fs)
        }
    }
}
