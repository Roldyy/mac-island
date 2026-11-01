import Foundation
import Testing
@testable import PortKit

/// Lane W4-D source gates, in the style of `PortPromptScrubTests`: they read the lane's files and fail on a re-import
/// (or an edit) that brings back a shell string, a second program, a prompt, a network call or an automatic wallpaper
/// change.
@Suite struct MediaToolsSourceTests {
    /// Every Swift file the lane owns or patches (path relative to Sources/PortKit).
    static let laneFiles = [
        "Bridge/MediaTools.swift",
        "Services/Media/MediaService.swift", "Services/Media/MediaSupport.swift",
        "Services/Media/MediaVideoTargetEncoder.swift",
        "Services/Wallpaper/WallpaperService.swift", "Services/Wallpaper/WallpaperStore.swift",
        "Services/Wallpaper/WallpaperSupport.swift",
        "UI/Media/MediaWorkspaceView.swift", "UI/MenuPanel/WallpaperSection.swift",
    ]

    static func isCode(_ line: Substring) -> Bool {
        !line.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("//")
    }

    /// Code lines only: (file, 1-based line number, text).
    static let codeLines: [(file: String, number: Int, text: String)] = {
        var result: [(String, Int, String)] = []
        for path in laneFiles {
            guard let file = PortSourceScrubTests.files.first(where: { $0.path == path }) else { continue }
            for (index, line) in file.lines.enumerated() where isCode(line) { result.append((path, index + 1, String(line))) }
        }
        return result
    }()

    static func hits(_ needles: [String], in lines: [(file: String, number: Int, text: String)] = codeLines) -> [String] {
        lines.filter { line in needles.contains { line.text.contains($0) } }.map { "\($0.file):\($0.number)" }
    }

    @Test func everyLaneFileIsPresent() {
        for path in Self.laneFiles {
            #expect(PortSourceScrubTests.files.contains { $0.path == path }, "\(path)")
        }
    }

    // MARK: External programs

    @Test func theOnlyExecutablesNamedAreTheOnesInTheToolTable() {
        var found: Set<String> = []
        for line in Self.codeLines {
            var rest = line.text[...]
            while let open = rest.firstIndex(of: "\"") {
                let tail = rest[rest.index(after: open)...]
                guard let close = tail.firstIndex(of: "\"") else { break }
                let literal = String(tail[..<close])
                if ["/usr/", "/bin/", "/sbin/", "/opt/"].contains(where: literal.hasPrefix) {
                    found.insert(literal)
                }
                rest = tail[tail.index(after: close)...]
            }
        }
        #expect(found == Set(MediaExternalTool.allCases.map(\.path)), "executables named in the lane: \(found)")
    }

    @Test func noShellStringNoSecondRunnerAndNoScriptHost() {
        let banned = ["\"/bin/sh\"", "\"/bin/bash\"", "\"/bin/zsh\"", "\"/usr/bin/env\"", "\"-c\"", "NSAppleScript",
                      "osascript", "AppleScriptRunner", "AdminShell", " system(", "(system(", "=system(", "popen(", "posix_spawn", "NSTask",
                      "ffmpeg", "sips", "qlmanage", "/usr/local/", "/opt/homebrew"]
        #expect(Self.hits(banned).isEmpty, "\(Self.hits(banned))")
    }

    @Test func aProcessIsCreatedInOneFileOnly() {
        let sites = Self.codeLines.filter { $0.text.contains("Process()") }.map { "\($0.file)" }
        #expect(sites == ["Bridge/MediaTools.swift"], "\(sites)")
    }

    @Test func everyShellRunInTheLaneIsTheAgentRestartAndTakesAnArray() {
        let runs = Self.codeLines.filter { $0.text.contains("Shell.run(") }
        #expect(!runs.isEmpty)
        for run in runs {
            #expect(run.text.contains("killall") && run.text.contains("[\"WallpaperAgent\"]"), "\(run.file):\(run.number)")
        }
    }

    @Test func theVideoConverterIsOnlyEverRunThroughTheRunner() {
        let service = Self.codeLines.filter { $0.file == "Services/Media/MediaService.swift" }
        #expect(service.contains { $0.text.contains("MediaAvconvertCommand.make(") })
        #expect(service.contains { $0.text.contains("MediaToolsRuntime.runner.run(") })
        #expect(!service.contains { $0.text.contains("executableURL") }, "no program path is set in the service any more")
        #expect(service.filter { $0.text.contains("process.run()") }.count == 1, "the one launch, under the service lock")
        #expect(service.contains { $0.text.contains("MediaService(replacesExistingOutputs: false)") }, "the shared service never replaces")
    }

    // MARK: No prompt, no network, no automatic change

    @Test func noPromptApiAndNoAdministratorOrConsentAsk() {
        let banned = PortPromptScrubTests.banned + ["requestAccess(", "requestAuthorization(", "requestFullAccess",
                                                    "consentToAutomate(", "AXIsProcessTrusted", "SMAppService",
                                                    "authorizationStatus", "NSOpenPanel().runModal"]
        #expect(Self.hits(banned).isEmpty, "\(Self.hits(banned))")
    }

    @Test func nothingInTheLaneTouchesTheNetwork() {
        let banned = ["URLSession", "URLRequest", "NSURLConnection", "http://", "https://", "WKWebView", "Data(contentsOf: URL(string",
                      "String(contentsOf: URL(string", "NWConnection", "CFNetwork"]
        #expect(Self.hits(banned).isEmpty, "a network call in the media or wallpaper code: \(Self.hits(banned))")
    }

    @Test func theWallpaperChangesOnlyFromAClickOnAPictureOrOnRestore() {
        let allFiles = PortSourceScrubTests.files
        func callers(_ needle: String, only path: String? = nil) -> [String] {
            var result: [String] = []
            for file in allFiles where path == nil || file.path == path {
                for (index, line) in file.lines.enumerated() where Self.isCode(line) && line.contains(needle) {
                    result.append("\(file.path):\(index + 1)")
                }
            }
            return result
        }
        // apply(): the gallery thumbnail button only.
        let applyCalls = callers("service.apply(", only: "UI/MenuPanel/WallpaperSection.swift") + callers("WallpaperService.shared.apply(")
        #expect(applyCalls.count == 1 && applyCalls[0].hasPrefix("UI/MenuPanel/WallpaperSection.swift"), "\(applyCalls)")
        // restorePrevious(): the restore button only.
        let restoreCalls = callers(".restorePrevious()")
        #expect(restoreCalls.count == 1 && restoreCalls[0].hasPrefix("UI/MenuPanel/WallpaperSection.swift"), "\(restoreCalls)")
        // The desktop image and the wallpaper store are written from the service and the restorer only.
        for needle in ["setDesktopImageURL(", "setImageOnAllSpaces("] {
            for site in callers(needle) {
                #expect(site.hasPrefix("Services/Wallpaper/") || site.hasPrefix("Bridge/MediaTools.swift"), "\(needle) at \(site)")
            }
        }
        #expect(callers("WallpaperStore.removeBackup(").isEmpty, "nothing deletes the way back any more")
    }

    @Test func theWallpaperServiceKeepsTheWayBackWhenTheFeatureStops() {
        let lines = Self.codeLines.filter { $0.file == "Services/Wallpaper/WallpaperService.swift" }
        #expect(!lines.contains { $0.text.contains("removeBackup") })
        #expect(lines.contains { $0.text.contains("captureIfNeeded()") }, "the point is taken before an apply")
        let capture = lines.first { $0.text.contains("captureIfNeeded()") }?.number ?? 0
        let firstWrite = lines.first { $0.text.contains("setDesktopImage(url, on: chosen") }?.number ?? 0
        #expect(capture > 0 && capture < firstWrite, "capture comes first")
    }

    @Test func theMigratedBookmarkKeysAreNotReadBackFromAnythingButTheHostDefaults() {
        // The migrator skips `wallpaperOwnBookmarks` (security-scoped data of another app identity): the service only
        // ever reads it from the host defaults, so a fresh install lists nothing until the user picks a folder.
        let lines = Self.codeLines.filter { $0.file == "Services/Wallpaper/WallpaperService.swift" && $0.text.contains("wallpaperOwnBookmarks") }
        #expect(lines.count == 2)
        for line in lines { #expect(line.text.contains("PortHost.defaults"), "\(line.number)") }
    }

    @Test func theStagingFolderIsCreatedByTheSystemAndRegisteredNeverMadeBesideTheSource() {
        let lines = Self.codeLines.filter { $0.file == "Services/Media/MediaSupport.swift" }
        #expect(lines.contains { $0.text.contains("MediaStaging.register(") })
        #expect(lines.contains { $0.text.contains("MediaStaging.discard(") })
        #expect(!lines.contains { $0.text.contains("removeItem(at: stagedURL.deletingLastPathComponent())") },
                "no blind removal of a parent folder")
        #expect(lines.contains { $0.text.contains(".itemReplacementDirectory") })
    }
}
