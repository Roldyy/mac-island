import Foundation
import Testing
@testable import PortKit

/// Lane W4-D: how a conversion is asked of the system. Pure: no process is started, nothing is read from the disk.
@Suite struct MediaToolsCommandTests {
    let source = URL(fileURLWithPath: "/Users/me/Movies/clip.mov")
    let staged = URL(fileURLWithPath: "/var/tmp/stage/Output.mp4")

    func make(_ source: URL, _ output: URL? = nil, preset: String = "Preset1280x720", start: Double = 1.5,
              duration: Double = 10, multiPass: Bool = false) throws -> MediaToolCommand {
        try MediaAvconvertCommand.make(source: source, output: output ?? staged, preset: preset, start: start,
                                       duration: duration, multiPass: multiPass)
    }

    // MARK: Argument construction

    @Test func avconvertIsOneFixedArrayRunFromAnAbsolutePath() throws {
        let command = try make(source)
        #expect(command.tool == .avconvert)
        #expect(command.executablePath == "/usr/bin/avconvert")
        #expect(command.arguments == [
            "--source", "/Users/me/Movies/clip.mov", "--preset", "Preset1280x720",
            "--output", "/var/tmp/stage/Output.mp4", "--replace", "--progress",
            "--start", "1.500", "--duration", "10.000",
        ])
        #expect(try make(source, multiPass: true).arguments.last == "--multiPass")
        #expect(try make(source, multiPass: false).arguments.contains("--multiPass") == false)
    }

    @Test func secondsAreWrittenWithADecimalPointWhateverTheRegion() {
        #expect(MediaAvconvertCommand.seconds(1234.5) == "1234.500")
        #expect(MediaAvconvertCommand.seconds(0.0004) == "0.000")
        #expect(MediaAvconvertCommand.seconds(7).contains(",") == false)
    }

    @Test func everyPresetTheServiceCanPickIsAllowedAndNothingElseIs() throws {
        let file = try #require(PortSourceScrubTests.files.first { $0.path == "Services/Media/MediaService.swift" })
        var literals: Set<String> = []
        for line in file.lines {
            var rest = line[...]
            while let open = rest.range(of: "\"Preset") {
                let tail = rest[open.upperBound...]
                guard let close = tail.firstIndex(of: "\"") else { break }
                literals.insert("Preset" + tail[..<close])
                rest = tail[tail.index(after: close)...]
            }
        }
        #expect(!literals.isEmpty)
        #expect(literals == MediaAvconvertCommand.allowedPresets, "\(literals.symmetricDifference(MediaAvconvertCommand.allowedPresets))")
        #expect(throws: MediaToolsError.unknownPreset("--output")) { try make(source, preset: "--output") }
        #expect(throws: MediaToolsError.unknownPreset("PresetHighestQuality; rm -rf ~")) {
            try make(source, preset: "PresetHighestQuality; rm -rf ~")
        }
    }

    // MARK: Path quoting and injection

    @Test func hostileFileNamesStayOneArgumentEachAndTheArgumentCountNeverChanges() throws {
        let names = [
            "/tmp/a b.mov", "/tmp/it's.mov", "/tmp/\"quoted\".mov", "/tmp/-rf.mov", "/tmp/--output.mov",
            "/tmp/a\nb.mov", "/tmp/a\r\nb.mov", "/tmp/$(touch pwned).mov", "/tmp/`id`.mov", "/tmp/a;b&c|d.mov",
            "/tmp/日本語 é.mov", "/tmp/ leading and trailing .mov", "/tmp/*.mov", "/tmp/~.mov", "/tmp/a\\b.mov",
            "/tmp/--preset PresetLowQuality.mov", "/tmp/dir with space/-x/file.mov",
        ]
        let baseline = try make(source).arguments.count
        for name in names {
            let url = URL(fileURLWithPath: name)
            let command = try make(url)
            #expect(command.arguments.count == baseline, "\(name.debugDescription)")
            #expect(command.arguments[1] == url.path, "the path is one element, verbatim: \(name.debugDescription)")
            #expect(command.arguments[1].hasPrefix("/"), "so a leading dash can never read as an option")
            #expect(command.arguments[0] == "--source" && command.arguments[2] == "--preset")
            #expect(command.arguments.filter { $0.hasPrefix("--") }.count == 7,
                    "only the seven fixed options start with dashes: \(name.debugDescription)")
            // The same name as the output.
            let asOutput = try make(source, url)
            #expect(asOutput.arguments[5] == url.path)
        }
    }

    @Test func aRelativeOrForeignURLIsRefusedAndALeadingDashFileBecomesAnAbsolutePath() throws {
        #expect(throws: MediaToolsError.invalidPath) { try make(URL(string: "clip.mov")!) }
        #expect(throws: MediaToolsError.invalidPath) { try make(URL(string: "-rf")!) }
        #expect(throws: MediaToolsError.invalidPath) { try make(URL(string: "https://example.com/a.mov")!) }
        #expect(throws: MediaToolsError.invalidPath) { try make(source, URL(string: "relative/out.mp4")!) }
        let dashed = try make(URL(fileURLWithPath: "-rf"))
        #expect(dashed.arguments[1].hasPrefix("/") && dashed.arguments[1].hasSuffix("/-rf"))
    }

    @Test func aNulByteOrAnOverlongPathIsRefused() throws {
        let nul = URL(fileURLWithPath: "/tmp/a\u{0}b.mov")
        if nul.path.utf8.contains(0) {
            #expect(throws: MediaToolsError.invalidPath) { try make(nul) }
        }
        let long = URL(fileURLWithPath: "/" + String(repeating: "a", count: 1100) + ".mov")
        #expect(throws: MediaToolsError.invalidPath) { try make(long) }
    }

    @Test func theSourceIsNeverTheOutputAndBadNumbersAreRefused() {
        #expect(throws: MediaToolsError.sameFile) { try make(source, source) }
        #expect(throws: MediaToolsError.invalidNumber) { try make(source, start: .nan) }
        #expect(throws: MediaToolsError.invalidNumber) { try make(source, start: -1) }
        #expect(throws: MediaToolsError.invalidNumber) { try make(source, duration: 0) }
        #expect(throws: MediaToolsError.invalidNumber) { try make(source, duration: .infinity) }
    }

    @Test func everyErrorHasAFrenchMessage() {
        for error in [MediaToolsError.invalidPath, .invalidNumber, .unknownPreset("x"), .sameFile] {
            #expect(!error.message.isEmpty && error.message != "\(error)")
        }
    }

    // MARK: Output names

    @Test func aFreeNameIsKeptAndATakenOneGetsTheFirstFreeNumber() {
        let candidate = URL(fileURLWithPath: "/Users/me/Movies/clip-compressed.mp4")
        #expect(MediaOutputNaming.availableURL(candidate, exists: { _ in false }) == candidate)
        var taken: Set<String> = [candidate.path]
        func free() -> URL { MediaOutputNaming.availableURL(candidate, exists: { taken.contains($0) }) }
        #expect(free().path == "/Users/me/Movies/clip-compressed 2.mp4")
        taken.insert("/Users/me/Movies/clip-compressed 2.mp4")
        #expect(free().path == "/Users/me/Movies/clip-compressed 3.mp4")
        taken.insert("/Users/me/Movies/clip-compressed 3.mp4")
        #expect(free().path == "/Users/me/Movies/clip-compressed 4.mp4")
    }

    @Test func aReservedNameCountsAsTakenAndTheSourceIsNeverReturned() {
        let sourcePath = "/Users/me/Pictures/photo.jpg"
        let candidate = URL(fileURLWithPath: sourcePath)
        let result = MediaOutputNaming.availableURL(candidate, reserved: ["/Users/me/Pictures/photo 2.jpg"],
                                                    exists: { $0 == sourcePath })
        #expect(result.path == "/Users/me/Pictures/photo 3.jpg")
        #expect(result.path != sourcePath)
    }

    @Test func theNumberedNameKeepsTheExtensionAndFitsAFileName() {
        let longBase = String(repeating: "é", count: 200)
        let candidate = URL(fileURLWithPath: "/tmp/\(longBase).gif")
        let result = MediaOutputNaming.availableURL(candidate, exists: { $0 == candidate.path })
        #expect(result.pathExtension == "gif")
        #expect(result.lastPathComponent.utf8.count <= 255, "\(result.lastPathComponent.utf8.count)")
        #expect(result.lastPathComponent.hasSuffix(" 2.gif"))
        let plain = MediaOutputNaming.availableURL(URL(fileURLWithPath: "/tmp/notes"), exists: { $0 == "/tmp/notes" })
        #expect(plain.path == "/tmp/notes 2", "no extension: no dot")
    }

    @Test func oddButLegalNamesAreKeptWhenNumbered() {
        for name in ["-dash.mp4", "new\nline.mp4", "sp ace.mp4", "quo\"te.mp4", "it's.mp4"] {
            let candidate = URL(fileURLWithPath: "/tmp/\(name)")
            let result = MediaOutputNaming.availableURL(candidate, exists: { $0 == candidate.path })
            #expect(result.deletingLastPathComponent().path == "/tmp", "\(name.debugDescription)")
            #expect(result.path != candidate.path && result.pathExtension == "mp4")
        }
    }
}
