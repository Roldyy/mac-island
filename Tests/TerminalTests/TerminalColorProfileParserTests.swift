import AppKit
import Foundation
import Testing
@testable import TerminalFeature

/// Fixtures are built in the test: nothing is read from disk but the temp files the file-reading tests write.
@Suite struct TerminalColorProfileParserTests {
    // MARK: Builders

    private func itermColor(_ r: Any, _ g: Any, _ b: Any, space: String? = "sRGB") -> [String: Any] {
        var dict: [String: Any] = ["Red Component": r, "Green Component": g, "Blue Component": b, "Alpha Component": 1.0]
        if let space { dict["Color Space"] = space }
        return dict
    }

    private func itermPlist(ansi: Int = 16, special: Bool = true, red: Any = 1.0, space: String? = "sRGB") throws -> Data {
        var root: [String: Any] = [:]
        for index in 0..<ansi { root["Ansi \(index) Color"] = itermColor(red, Double(index) / 15, 0.25, space: space) }
        if special {
            root["Foreground Color"] = itermColor(0.9, 0.9, 0.9)
            root["Background Color"] = itermColor(0.0, 0.1, 0.2)
            root["Cursor Color"] = itermColor(1, 1, 0)
            root["Selection Color"] = itermColor(0.2, 0.3, 0.4)
        }
        return try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
    }

    private func archived(_ color: NSColor) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true)
    }

    private func terminalPlist(colors: Int = 20, name: String? = "Ocean", font: Bool = true, hostile: Bool = false) throws -> Data {
        let keys = [
            "ANSIBlackColor", "ANSIRedColor", "ANSIGreenColor", "ANSIYellowColor", "ANSIBlueColor", "ANSIMagentaColor",
            "ANSICyanColor", "ANSIWhiteColor", "ANSIBrightBlackColor", "ANSIBrightRedColor", "ANSIBrightGreenColor",
            "ANSIBrightYellowColor", "ANSIBrightBlueColor", "ANSIBrightMagentaColor", "ANSIBrightCyanColor",
            "ANSIBrightWhiteColor", "BackgroundColor", "TextColor", "CursorColor", "SelectionColor",
        ]
        var root: [String: Any] = ["type": "Window Settings"]
        for (index, key) in keys.prefix(colors).enumerated() {
            root[key] = try archived(NSColor(srgbRed: CGFloat(index) / 20, green: 0.5, blue: 0.25, alpha: 1))
        }
        if let name { root["name"] = name }
        if font, let nsFont = NSFont(name: "Menlo-Regular", size: 13) {
            root["Font"] = try NSKeyedArchiver.archivedData(withRootObject: nsFont, requiringSecureCoding: true)
        }
        if hostile {
            // A blob that is not an NSColor: secure decoding limited to NSColor must refuse it.
            root["ANSIBlackColor"] = try NSKeyedArchiver.archivedData(withRootObject: NSURL(string: "https://example.invalid")!, requiringSecureCoding: true)
            root["ANSIRedColor"] = try NSKeyedArchiver.archivedData(withRootObject: NSAttributedString(string: "x"), requiringSecureCoding: true)
        }
        return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }

    // MARK: iTerm

    @Test func validITermProfileParses() throws {
        let result = try TerminalColorProfileParser.parse(data: itermPlist(), fileName: "Solarized Dark.itermcolors")
        #expect(result.foundColors == 20)
        #expect(result.profile.name == "Solarized Dark")
        #expect(result.profile.ansi.count == 16)
        #expect(result.profile.ansi[15].green == 1)
        #expect(result.profile.background == TerminalRGB(0.0, 0.1, 0.2))
        #expect(result.profile.cursor == TerminalRGB(1, 1, 0))
    }

    @Test func missingColorsFallBackToTheDefaultTheme() throws {
        // 8 ANSI colours only, no specials: accepted, the rest comes from the current theme.
        let result = try TerminalColorProfileParser.parse(data: itermPlist(ansi: 8, special: false), fileName: "mini.itermcolors")
        #expect(result.foundColors == 8)
        #expect(result.profile.ansi[8] == TerminalColorProfile.defaultAnsi[8])
        #expect(result.profile.foreground == TerminalColorProfile.defaultForeground)
        #expect(result.profile.cursor == result.profile.foreground)
        #expect(result.profile.selection == TerminalColorProfile.defaultSelection)
    }

    @Test func fewerThanEightColorsIsRefusedInFrench() throws {
        let data = try itermPlist(ansi: 7, special: false)
        #expect(throws: TerminalColorProfileError.tooFewColors(found: 7)) {
            try TerminalColorProfileParser.parse(data: data, fileName: "x.itermcolors")
        }
        #expect(TerminalColorProfileError.tooFewColors(found: 7).errorDescription?.contains("au moins 8") == true)
    }

    @Test func componentsAreClamped() throws {
        let clamped = try TerminalColorProfileParser.parse(data: itermPlist(red: 7.5), fileName: "x.itermcolors")
        #expect(clamped.profile.ansi.allSatisfy { $0.red == 1 })
    }

    @Test func nanOnEveryAnsiColorIsRefused() throws {
        let data = try itermPlist(red: Double.nan)
        #expect(throws: TerminalColorProfileError.tooFewColors(found: 4)) {
            try TerminalColorProfileParser.parse(data: data, fileName: "x.itermcolors")
        }
    }

    @Test func p3ColorsConvertToSRGB() throws {
        let sRGB = try TerminalColorProfileParser.parse(data: itermPlist(space: "sRGB"), fileName: "a.itermcolors")
        let p3 = try TerminalColorProfileParser.parse(data: itermPlist(space: "P3"), fileName: "a.itermcolors")
        #expect(sRGB.profile.ansi[3] != p3.profile.ansi[3])
        #expect(p3.profile.ansi.allSatisfy { (0...1).contains($0.red) && (0...1).contains($0.green) && (0...1).contains($0.blue) })
    }

    @Test func booleanComponentsAreNotNumbers() {
        #expect(ITermColorsReader.color(["Red Component": true, "Green Component": 0.5, "Blue Component": 0.5]) == nil)
    }

    // MARK: Terminal.app

    @Test func validTerminalAppProfileParses() throws {
        let result = try TerminalColorProfileParser.parse(data: terminalPlist(), fileName: "Ocean.terminal")
        #expect(result.foundColors == 20)
        #expect(result.profile.name == "Ocean")
        #expect(result.profile.fontName == "Menlo-Regular")
        #expect(result.profile.fontSize == 13)
        #expect(abs(result.profile.ansi[4].red - 4.0 / 20) < 0.01)
        #expect(abs(result.profile.foreground.red - 17.0 / 20) < 0.01)
    }

    @Test func terminalAppNameFallsBackToTheFileName() throws {
        let result = try TerminalColorProfileParser.parse(data: terminalPlist(name: nil, font: false), fileName: "Mon thème.terminal")
        #expect(result.profile.name == "Mon thème")
        #expect(result.profile.fontName == nil)
    }

    @Test func nonColorBlobsFailClosed() throws {
        let data = try terminalPlist(hostile: true)
        let result = try TerminalColorProfileParser.parse(data: data, fileName: "h.terminal")
        // The two hostile blobs decode to nothing: 18 colours remain, the two slots use the default theme.
        #expect(result.foundColors == 18)
        #expect(result.profile.ansi[0] == TerminalColorProfile.defaultAnsi[0])
        #expect(result.profile.ansi[1] == TerminalColorProfile.defaultAnsi[1])
    }

    @Test func terminalAppWithTooFewColorsIsRefused() throws {
        let data = try terminalPlist(colors: 5, font: false)
        #expect(throws: TerminalColorProfileError.tooFewColors(found: 5)) {
            try TerminalColorProfileParser.parse(data: data, fileName: "x.terminal")
        }
    }

    // MARK: Refusals

    @Test func truncatedFileIsUnreadable() throws {
        let full = try itermPlist()
        #expect(throws: TerminalColorProfileError.unreadable) {
            try TerminalColorProfileParser.parse(data: full.prefix(full.count / 2), fileName: "x.itermcolors")
        }
        #expect(throws: TerminalColorProfileError.unreadable) {
            try TerminalColorProfileParser.parse(data: Data(), fileName: "x.itermcolors")
        }
    }

    @Test func hugeFileIsRefusedBeforeParsing() {
        let huge = Data(repeating: 0x20, count: TerminalColorProfileParser.maxFileBytes + 1)
        #expect(throws: TerminalColorProfileError.fileTooLarge) {
            try TerminalColorProfileParser.parse(data: huge, fileName: "x.itermcolors")
        }
    }

    @Test func wrongExtensionIsRefused() throws {
        let data = try itermPlist()
        for name in ["x.json", "x.plist", "x", "x.itermcolors.sh", "x.conf"] {
            #expect(throws: TerminalColorProfileError.unsupportedType, "\(name)") {
                try TerminalColorProfileParser.parse(data: data, fileName: name)
            }
        }
    }

    @Test func wrongContentForTheTypeIsRefused() throws {
        let array = try PropertyListSerialization.data(fromPropertyList: [1, 2, 3], format: .xml, options: 0)
        #expect(throws: TerminalColorProfileError.notAColorProfile) {
            try TerminalColorProfileParser.parse(data: array, fileName: "x.itermcolors")
        }
        // An iTerm file under a .terminal name carries no archived colours.
        let iterm = try itermPlist()
        #expect(throws: TerminalColorProfileError.tooFewColors(found: 0)) {
            try TerminalColorProfileParser.parse(data: iterm, fileName: "x.terminal")
        }
        #expect(throws: TerminalColorProfileError.unreadable) {
            try TerminalColorProfileParser.parse(data: Data("not a plist at all".utf8), fileName: "x.terminal")
        }
    }

    // MARK: Hostile name

    @Test func hostileNameIsSanitised() {
        let hostile = "\u{202E}evil\u{0}\n\t  name\u{200B}" + String(repeating: "x", count: 500)
        let clean = TerminalColorProfile.sanitizedName(hostile)
        #expect(clean.count <= TerminalColorProfile.maxNameLength)
        #expect(!clean.unicodeScalars.contains { $0.value == 0x202E || $0.value == 0 || $0.value == 0x200B || $0.value == 10 })
        #expect(clean.hasPrefix("evil name"))
        #expect(TerminalColorProfile.sanitizedName("\u{0}\u{1}  ") == TerminalColorProfile.fallbackName)
    }

    @Test func hostileFileNameBecomesASafeProfileName() throws {
        let result = try TerminalColorProfileParser.parse(data: itermPlist(), fileName: "../../etc/\u{202E}pwn\u{0}.itermcolors")
        #expect(!result.profile.name.unicodeScalars.contains { $0.value == 0x202E || $0.value == 0 })
    }

    @Test func nanComponentCannotBuildAColor() {
        #expect(TerminalRGB.validated(.nan, 0, 0) == nil)
        #expect(TerminalRGB.validated(0, .infinity, 0) == nil)
        #expect(TerminalRGB(.nan, 2, -1) == TerminalRGB(0, 1, 0))
    }

    // MARK: Reading a file

    @Test func readsAFileFromDiskWithinTheCap() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tcp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let good = directory.appendingPathComponent("Nuit.itermcolors")
        try itermPlist().write(to: good)
        #expect(try TerminalColorProfileParser.read(url: good).profile.name == "Nuit")
        let big = directory.appendingPathComponent("big.itermcolors")
        try Data(repeating: 0x20, count: TerminalColorProfileParser.maxFileBytes + 10).write(to: big)
        #expect(throws: TerminalColorProfileError.fileTooLarge) { try TerminalColorProfileParser.read(url: big) }
        let missing = directory.appendingPathComponent("absent.itermcolors")
        #expect(throws: TerminalColorProfileError.unreadable) { try TerminalColorProfileParser.read(url: missing) }
    }
}
