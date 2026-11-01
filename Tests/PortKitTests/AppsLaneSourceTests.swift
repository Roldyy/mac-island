import Foundation
import Testing
@testable import PortKit

/// Lane W7C and W7D, source gates: what the app-updates, Homebrew and uninstaller code may start, reach and delete.
/// They read the files by path, like `PortSourceScrubTests`, so a re-import or a later edit that brings a shell, an
/// Apple Event, a second removal call or a new host back fails here.
@Suite struct AppsLaneSourceTests {
    /// Directories and hand-written files of the two lanes (paths relative to Sources/PortKit).
    static let laneFiles: [(path: String, text: String, lines: [Substring])] = {
        PortSourceScrubTests.files.compactMap { file in
            let inLane = file.path.hasPrefix("Services/Homebrew/") || file.path.hasPrefix("Services/AppUpdates/")
                || file.path.hasPrefix("Services/Uninstall/") || file.path.hasPrefix("UI/AppUpdates/")
                || file.path.hasPrefix("UI/Uninstall/") || file.path == "UI/HomebrewOperationStatusView.swift"
                || file.path == "Bridge/AppUpdates.swift" || file.path == "Bridge/Uninstaller.swift"
            guard inLane else { return nil }
            return (file.path, file.lines.joined(separator: "\n"), file.lines)
        }
    }()

    static func codeLines(_ file: (path: String, text: String, lines: [Substring])) -> [(number: Int, line: Substring)] {
        file.lines.enumerated().compactMap { index, line in
            line.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("//") ? nil : (index + 1, line)
        }
    }

    static func file(_ path: String) -> (path: String, text: String, lines: [Substring]) {
        laneFiles.first { $0.path == path } ?? (path, "", [])
    }

    @Test func theLaneFilesAreThere() {
        #expect(Self.laneFiles.count >= 15)
        for path in ["Services/Homebrew/HomebrewManager.swift", "Services/AppUpdates/AppUpdatesService.swift",
                     "Services/Uninstall/AppUninstaller.swift", "Bridge/AppUpdates.swift", "Bridge/Uninstaller.swift"] {
            #expect(Self.file(path).text.isEmpty == false, "\(path)")
        }
    }

    // MARK: No shell, no Apple Events, no Terminal launch

    @Test func noLaneCodeStartsAShellOrScriptsAnotherApp() {
        let banned = ["AppleScriptRunner", "NSAppleScript", "osascript", "NSUserAppleScriptTask", "tell application",
                      "\"/bin/sh\"", "\"/bin/zsh\"", "\"/bin/bash\"", "\"/usr/bin/env\"", "popen(", "posix_spawn(",
                      "consentToAutomate"]
        var offenders: [String] = []
        // C `system(` as a call, not SwiftUI's `.system(size:)` font or a longer name.
        let systemCall = try! NSRegularExpression(pattern: #"(^|[^.\w])system\("#)
        for file in Self.laneFiles {
            for (number, line) in Self.codeLines(file) {
                let text = String(line)
                let range = NSRange(location: 0, length: (text as NSString).length)
                let isSystemCall = systemCall.firstMatch(in: text, range: range) != nil
                if isSystemCall || banned.contains(where: { line.contains($0) }) { offenders.append("\(file.path):\(number)") }
            }
        }
        #expect(offenders.isEmpty, "a shell or an Apple Event in the lane: \(offenders)")
    }

    @Test func everyProcessTheLanesStartIsAFixedArgvOfAKnownProgram() {
        // `Process()` and `BoundedProcessRunner.run` appear only with `command.executable`, and every
        // HomebrewCommand is built on the located brew or on /usr/bin/mdfind.
        var offenders: [String] = []
        for file in Self.laneFiles {
            for (number, line) in Self.codeLines(file) {
                if (line.contains("executableURL =") || line.contains("BoundedProcessRunner.run")
                    || line.contains("runInNewSession(")) && !line.contains("command.executable") {
                    offenders.append("\(file.path):\(number)")
                }
            }
            let pattern = #"HomebrewCommand\(\s*executable:\s*([^,)]+)"#
            let regex = try! NSRegularExpression(pattern: pattern)
            let text = file.text as NSString
            for match in regex.matches(in: file.text, range: NSRange(location: 0, length: text.length)) {
                let argument = text.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                if !["brewPath", "\"/usr/bin/mdfind\""].contains(argument) {
                    // The login-shell command of `HomebrewEnvironment` stays for the agent usage code only.
                    if file.path == "Services/Homebrew/HomebrewEnvironment.swift", argument == "shellPath" { continue }
                    offenders.append("\(file.path): HomebrewCommand(executable: \(argument))")
                }
            }
        }
        #expect(offenders.isEmpty, "an unknown program: \(offenders)")
    }

    @Test func brewIsNeverStartedThroughTheLoginShell() {
        for path in ["Services/Homebrew/HomebrewManager.swift", "Services/AppUpdates/AppUpdatesService.swift",
                     "Bridge/AppUpdates.swift"] {
            let file = Self.file(path)
            for (number, line) in Self.codeLines(file) {
                #expect(!line.contains("loginShell") && !line.contains("exportsFromLoginShell"), "\(path):\(number)")
            }
        }
        let env = Self.file("Services/Homebrew/HomebrewEnvironment.swift")
        let forBrew = env.lines.firstIndex { $0.contains("static let forBrew") }
        #expect(forBrew != nil)
        if let forBrew {
            #expect(!env.lines[forBrew].contains("loginShell") && !env.lines[forBrew + 1].contains("loginShell"))
            #expect(env.lines[forBrew].contains("environment(from:"))
        }
    }

    @Test func theHomebrewInstallerCommandIsOnlyEverCopied() {
        var uses: [String] = []
        for file in PortSourceScrubTests.files {
            for (number, line) in file.lines.enumerated() where line.contains("HomebrewCommandBuilder.installerCommand")
                || line.contains("static let installerCommand") {
                uses.append("\(file.path):\(number + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        // The declaration, and the one call that hands it to the pasteboard.
        #expect(uses.count == 2, "\(uses)")
        #expect(uses.contains { $0.contains("static let installerCommand") })
        #expect(uses.contains { $0.contains("copyForTerminal(command: HomebrewCommandBuilder.installerCommand)") })
        let manager = Self.file("Services/Homebrew/HomebrewManager.swift").text
        #expect(manager.contains("NSPasteboard.general") && manager.contains("copyForTerminal"))
    }

    // MARK: Trash only, one removal call

    @Test func theUninstallerHasNoRemovalCallButTheTrash() {
        let banned = ["removeItem(", "unlink(", "rmdir(", "FileManager.default.replaceItem",
                      "NSWorkspace.shared.recycle", "delete targets"]
        var trash = 0
        var offenders: [String] = []
        for file in Self.laneFiles where file.path.hasPrefix("Services/Uninstall/") {
            for (number, line) in Self.codeLines(file) {
                if line.contains("trashItem(") { trash += 1 }
                if banned.contains(where: { line.contains($0) }) { offenders.append("\(file.path):\(number)") }
            }
        }
        #expect(trash == 1, "exactly one Trash move, found \(trash)")
        #expect(offenders.isEmpty, "a way to delete that is not the Trash: \(offenders)")
    }

    @Test func removalRunsOnlyAfterTheReviewWasConfirmed() {
        let source = Self.file("Services/Uninstall/AppUninstaller.swift")
        let calls = Self.codeLines(source).filter { $0.line.contains("performRemoval()") }
        // The declaration `private func performRemoval()` and the single call in `confirmReview`.
        #expect(calls.count == 2, "\(calls.map(\.number))")
        #expect(calls.contains { $0.line.contains("func performRemoval()") })
        let text = source.text
        let confirm = text.range(of: "func confirmReview")
        let perform = text.range(of: "        performRemoval()\n")
        #expect(confirm != nil && perform != nil)
        if let confirm, let perform { #expect(confirm.lowerBound < perform.lowerBound) }
        // `removeSelected()` itself only builds a plan.
        let asks = text.range(of: "func removeSelected()").map { start -> String in
            let rest = text[start.lowerBound...]
            let end = rest.range(of: "    func cancelReview()")?.lowerBound ?? rest.endIndex
            return String(rest[..<end])
        } ?? ""
        #expect(asks.contains("reviewGate.request") && !asks.contains("trashItem") && !asks.contains("phase = .removing"))
    }

    @Test func theScanAndTheMoveBothAskThePathPolicy() {
        let text = Self.file("Services/Uninstall/AppUninstaller.swift").text
        #expect(text.components(separatedBy: "UninstallPathPolicy.isRemovable").count - 1 == 2,
                "once when the list is built, once at the moment of the move")
        for system in ["\"/Library\"", "/private/var/db/receipts", "/Users/Shared/Library"] {
            let roots = text.components(separatedBy: "\n").filter { $0.contains("URL(fileURLWithPath: \(system)") }
            #expect(roots.isEmpty, "\(system) is no longer a scan root")
        }
    }

    // MARK: Network

    @Test func theLanesReachOnlyTheirKnownHosts() {
        let allowed: Set<String> = [
            "formulae.brew.sh", "itunes.apple.com", "uclient-api.itunes.apple.com", "github.com",
            "raw.githubusercontent.com",  // text of the copied installer command, never fetched by the app
            "www.andymatuschak.org",  // an XML namespace, not a request
            "showUpdatesPage",  // `macappstore://showUpdatesPage`: opens the App Store's own update tab
        ]
        var offenders: [String] = []
        for file in Self.laneFiles {
            for (number, line) in Self.codeLines(file) {
                var rest = line[...]
                while let range = rest.range(of: "://") {
                    let hostStart = range.upperBound
                    let host = rest[hostStart...].prefix { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
                    if !host.isEmpty, !allowed.contains(String(host)) { offenders.append("\(file.path):\(number): \(host)") }
                    rest = rest[hostStart...]
                }
            }
        }
        #expect(offenders.isEmpty, "an unknown host: \(offenders)")
    }

    @Test func urlSessionIsOnlyInTheTwoNetworkServices() {
        var files = Set<String>()
        for file in Self.laneFiles where file.lines.contains(where: { $0.contains("URLSession") }) { files.insert(file.path) }
        #expect(files == ["Services/AppUpdates/AppUpdatesService.swift", "Services/AppUpdates/AppUpdateFeedLoader.swift",
                          "Services/Homebrew/HomebrewManager.swift"], "\(files.sorted())")
        // The cleanup, the locator and the review views never touch the network.
        for path in ["Bridge/AppUpdates.swift", "Bridge/Uninstaller.swift"] {
            #expect(!Self.file(path).text.contains("URLSession"), "\(path)")
        }
    }

    // MARK: Prompts and wording

    @Test func theUpdatePageNoLongerRaisesTheNotificationPrompt() {
        let url = PortSourceScrubTests.portKit.appendingPathComponent("UI/Settings/AppUpdatesSettings.swift")
        let source = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        #expect(!source.isEmpty && !source.contains("requestPermission") && source.contains("AppUpdatesNotificationHint()"))
    }

    @Test func noPlaceholderWordingInTheLaneTexts() {
        for text in [HomebrewCleanupText.title, HomebrewCleanupText.caption, HomebrewCleanupText.previewButton,
                     HomebrewCleanupText.confirm, HomebrewCleanupText.nothing, AppUpdatesText.notificationNote,
                     AppUpdatesText.notificationButton] {
            let lower = text.lowercased()
            #expect(!text.isEmpty && !lower.contains("bientôt") && !lower.contains("bientot") && !lower.contains("coming soon"))
        }
    }

    @Test func theTerminalStringsTellThePersonTheCommandIsCopied() {
        for name in ["Core/Localizations/Strings+French.swift", "Core/Localization.swift"] {
            let url = PortSourceScrubTests.portKit.appendingPathComponent(name)
            let source = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            #expect(source.contains("homebrewOpenTerminal: \"Copier la commande\"")
                    || source.contains("homebrewOpenTerminal: \"Copy the command\""), "\(name)")
            #expect(!source.contains("peut ouvrir Terminal") && !source.contains("can open Terminal"), "\(name)")
            #expect(!source.contains("\"Ouvrir Terminal\"") && !source.contains("\"Open Terminal\""), "\(name)")
        }
    }
}
