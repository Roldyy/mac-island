import AppKit
import Foundation
import Testing
@testable import PortKit

/// Lane W5-C safety: what the command bar may run, open and read. Fakes and temporary files only: no process is
/// started, no browser opened, no hotkey registered, no panel shown, no private data read.
@MainActor
@Suite(.serialized) struct CommandBarSafetyTests {
    // MARK: Scripts: the person's own executable, on an explicit selection

    @Test func aSavedScriptNeverRunsBecauseTypingPaused() {
        #expect(CommandBarScriptRunner.runsWhileTyping == false)
        let runner = CommandBarScriptRunner()
        var link = CommandBarLink()
        link.name = "report"
        link.kind = .script
        link.destination = "/usr/bin/true"
        link.runsWithoutArgument = true
        runner.schedule(link: link, argument: "anything typed")
        runner.schedule(link: link, argument: "")
        #expect(runner.isAwaiting == false, "nothing pending, nothing in flight: no process was ever started")
        #expect(runner.cachedResult(linkID: link.id, argument: "anything typed") == nil)
    }

    @Test func aScriptRunsOnlyFromTheRowSelectionOrItsOwnShortcut() throws {
        let catalog = try Self.source("Sources/PortKit/Services/CommandBar/CommandBarCatalog.swift")
        // The two callers of a run: Return on the row (`runScript`) and the row's own shortcut (`runScriptDirectly`).
        #expect(catalog.components(separatedBy: "scriptRunner.runNow(").count - 1 == 2, "runNow, from runScript only")
        let service = try Self.source("Sources/PortKit/Services/CommandBar/CommandBarService.swift")
        #expect(service.contains("scriptRunner.schedule(link:"), "the old call site still exists, and it is inert")
        #expect(CommandBarScriptRunner.runsWhileTyping == false)
        let runner = try Self.source("Sources/PortKit/Services/CommandBar/CommandBarScriptRunner.swift")
        #expect(runner.contains("guard Self.runsWhileTyping else { return }"))
    }

    @Test func onlyAnAbsoluteExecutableFileWithNoPlaceholderIsEverRun() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cb-scripts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let good = dir.appendingPathComponent("good.sh")
        let plain = dir.appendingPathComponent("plain.txt")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: good)
        try Data("hello".utf8).write(to: plain)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: good.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plain.path)

        #expect(PortCommandBarScripts.executablePath(for: good.path) == good.path)
        #expect(PortCommandBarScripts.executablePath(for: "  \(good.path)  ") == good.path, "edges trimmed")
        #expect(PortCommandBarScripts.executablePath(for: plain.path) == nil, "not executable")
        #expect(PortCommandBarScripts.executablePath(for: dir.path) == nil, "a folder is not a script")
        #expect(PortCommandBarScripts.executablePath(for: dir.appendingPathComponent("missing.sh").path) == nil)
        #expect(PortCommandBarScripts.executablePath(for: "good.sh") == nil, "relative: refused")
        #expect(PortCommandBarScripts.executablePath(for: "") == nil)
        #expect(PortCommandBarScripts.executablePath(for: "echo hi; rm -rf /") == nil, "a command line is not a path")
        #expect(PortCommandBarScripts.executablePath(for: "/bin/sh -c \"touch x\"") == nil, "arguments in the path: refused")
        #expect(PortCommandBarScripts.executablePath(for: good.path + "\nrm -rf ~") == nil)
        #expect(PortCommandBarScripts.executablePath(for: good.path + "\t") == good.path, "tabs and spaces at the edges only")
        #expect(PortCommandBarScripts.executablePath(for: good.path + "\r") == nil, "a line break is never a path")
        #expect(PortCommandBarScripts.executablePath(for: "/tmp/a\0b") == nil)
    }

    @Test func textNeverBuildsTheScriptPath() {
        for token in CommandBarLinkPlaceholder.allCases.map(\.token) {
            #expect(PortCommandBarScripts.executablePath(for: "/usr/bin/\(token)") == nil, "\(token)")
            #expect(PortCommandBarScripts.executablePath(for: "/usr/bin/true\(token)") == nil, "\(token)")
        }
        // The clipboard, the selection and the date placeholders are for web links only: a script's path is never expanded.
        #expect(CommandBarLink.Kind.script.symbolName == "terminal")
        let expanded = CommandBarLinks.expand("https://example.com/?q={query}&c={clipboard}", kind: .link,
                                              query: "a&b", clipboard: "x y", selection: "", date: "")
        #expect(expanded == "https://example.com/?q=a%26b&c=x%20y", "web link values are escaped")
    }

    @Test func theTypedWordsAreOneArgumentNeverSplitNeverAShellString() {
        #expect(PortCommandBarScripts.arguments(forTyped: "a b; rm -rf ~ $(whoami) `id` | cat") == ["a b; rm -rf ~ $(whoami) `id` | cat"])
        #expect(PortCommandBarScripts.arguments(forTyped: "") == [""])
        #expect(PortCommandBarScripts.arguments(forTyped: "a\0b") == ["ab"], "NUL removed")
        #expect(PortCommandBarScripts.arguments(forTyped: "line1\nline2").count == 1)
        let long = String(repeating: "x", count: 5000)
        #expect(PortCommandBarScripts.arguments(forTyped: long)[0].count == PortCommandBarScripts.maxArgumentLength)
    }

    @Test func noCommandBarFileRunsAShellAnInterpreterOrAppleScript() throws {
        for path in try Self.commandBarFiles() {
            let text = try Self.source(path)
            for needle in ["/bin/sh", "/bin/zsh", "/bin/bash", "osascript", "NSAppleScript", "NSUserAppleScriptTask", "popen(",
                           "Process()", "-c\""] {
                #expect(!text.contains(needle), "\(path) contains \(needle)")
            }
            // The C `system(` call, not SwiftUI's `.system(size:)`.
            let cSystem = try NSRegularExpression(pattern: #"(?<![.\w])system\("#)
            #expect(cSystem.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil, "\(path) calls system(")
        }
        // The only processes the bar starts go through `Shell.run` with a fixed path and an argument array.
        let service = try Self.source("Sources/PortKit/Services/CommandBar/CommandBarService.swift")
        #expect(service.contains("\"/usr/bin/mdfind\""))
    }

    // MARK: Web search: https only, encoded, opened on Return only

    @Test func everySearchTemplateIsHttpsAndPutsTheWordsInTheQueryString() {
        let ids = PortCommandBarWebSearch.engines.map(\.id)
        #expect(ids == ["duckduckgo", "google", "bing", "ecosia", "qwant"] && Set(ids).count == ids.count)
        for engine in PortCommandBarWebSearch.engines {
            #expect(PortCommandBarWebSearch.isValid(template: engine.template), "\(engine.id)")
            #expect(engine.template.hasPrefix("https://"))
            let url = PortCommandBarWebSearch.url(forQuery: "mac island", template: engine.template)
            #expect(url?.scheme == "https" && url?.query == "q=mac%20island", "\(engine.id)")
            #expect(url?.host == URL(string: engine.template.replacingOccurrences(of: "{query}", with: "x"))?.host)
        }
        #expect(PortCommandBarWebSearch.defaultEngineID == "duckduckgo")
    }

    @Test func theTemplateRulesRefuseWhatIsNotHttpsOrPutsTheWordsInTheHost() {
        for bad in ["http://duckduckgo.com/?q={query}", "file:///etc/passwd?q={query}", "javascript:alert({query})",
                    "https://{query}.example.com/", "https://example.com/{query}?x=1", "https://example.com/?q=",
                    "https://example.com/?q={query}&r={query}", "https://?q={query}", "ftp://x/?q={query}", ""] {
            #expect(!PortCommandBarWebSearch.isValid(template: bad), "\(bad)")
            #expect(PortCommandBarWebSearch.url(forQuery: "x", template: bad) == nil, "\(bad)")
        }
    }

    @Test func theQueryIsEncodedToTheUnreservedSetAndCapped() {
        let template = PortCommandBarWebSearch.engines[0].template
        func query(_ typed: String) -> String? { PortCommandBarWebSearch.url(forQuery: typed, template: template)?.absoluteString }
        #expect(query("a&b=c#d") == "https://duckduckgo.com/?q=a%26b%3Dc%23d")
        #expect(query("é ü/\\?") == "https://duckduckgo.com/?q=%C3%A9%20%C3%BC%2F%5C%3F")
        #expect(query("  spaced out \n") == "https://duckduckgo.com/?q=spaced%20out")
        #expect(query("https://evil.example/?x") == "https://duckduckgo.com/?q=https%3A%2F%2Fevil.example%2F%3Fx", "a typed URL stays a value")
        #expect(query("100% + 1") == "https://duckduckgo.com/?q=100%25%20%2B%201")
        #expect(query("") == nil && query("   \n\t") == nil)
        let long = query(String(repeating: "a", count: 500)) ?? ""
        #expect(long.count == "https://duckduckgo.com/?q=".count + PortCommandBarWebSearch.maxQueryLength)
        for typed in ["a%00b", "\u{0}", "../..", "';--", "<script>"] {
            let url = PortCommandBarWebSearch.url(forQuery: typed, template: template)
            #expect(url?.host == "duckduckgo.com" && url?.path == "/" && url?.scheme == "https", "\(typed)")
        }
    }

    @Test func theWebRowIsTheLastOneAndOnlyBuildsTheAddressUntilReturn() {
        PortHostFixture.isolated { defaults in
            let row = PortCommandBarWebSearch.entry(for: "swift  concurrency", defaults: defaults)
            #expect(row?.id == "websearch.query" && row?.countsUsage == false)
            #expect(row?.title == "Rechercher « swift  concurrency » sur le web")
            #expect(row?.subtitle.contains("DuckDuckGo") == true && row?.subtitle.contains("navigateur") == true)
            #expect(CommandBarPreferences.source(ofRowID: row?.id ?? "") == .actions)
            #expect(PortCommandBarWebSearch.entry(for: "   ", defaults: defaults) == nil, "nothing to search")
            defaults.set("google", forKey: PortCommandBarWebSearch.engineKey)
            #expect(PortCommandBarWebSearch.entry(for: "x", defaults: defaults)?.subtitle.contains("Google") == true)
            defaults.set("not-an-engine", forKey: PortCommandBarWebSearch.engineKey)
            #expect(PortCommandBarWebSearch.selectedEngine(in: defaults).id == "duckduckgo", "an unknown choice falls back")
            defaults.set(false, forKey: PortCommandBarWebSearch.enabledKey)
            #expect(PortCommandBarWebSearch.entry(for: "x", defaults: defaults) == nil, "the old switch still turns it off")
            #expect(PortCommandBarWebSearch.rowTitle(for: String(repeating: "w", count: 90)).contains("…"))
        }
    }

    @Test func theWebRowIsAppendedAfterTheRankingAndOnlyWhenNoAddressWasTyped() throws {
        let service = try Self.source("Sources/PortKit/Services/CommandBar/CommandBarService.swift")
        #expect(service.contains("if openURL == nil, let web = PortCommandBarWebSearch.entry(for: trimmed) { result.append(web) }"))
        let range = try #require(service.range(of: "PortCommandBarWebSearch.entry(for: trimmed)"))
        let tail = service[range.upperBound...].prefix(60)
        #expect(tail.contains("return result"), "the last statement of the search")
    }

    @Test func nothingInTheBarMakesANetworkCall() throws {
        for path in try Self.commandBarFiles() {
            let text = try Self.source(path)
            for needle in ["URLSession", "URLRequest", "NWConnection", "CFNetwork", "NSURLConnection", "WKWebView",
                           "Data(contentsOf: URL(string", "String(contentsOf: URL(string"] {
                #expect(!text.contains(needle), "\(path) contains \(needle)")
            }
        }
    }

    @Test func anOpenedAddressComesFromARowTheBarRunsNeverFromAScan() throws {
        // Every `NSWorkspace.shared.open` in the bar sits inside a row's `run`: nothing opens while typing.
        let catalog = try Self.source("Sources/PortKit/Services/CommandBar/CommandBarCatalog.swift")
        let lines = catalog.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() where line.contains("NSWorkspace.shared.open(") {
            let window = lines[max(0, index - 45)...index].joined(separator: "\n")
            #expect(window.contains("run:") || window.contains("static func open") || window.contains("withClipboard"),
                    "line \(index + 1): \(line)")
        }
    }

    // MARK: Query text: never logged, never sent

    @Test func noQueryTextIsEverLogged() throws {
        for path in try Self.commandBarFiles() {
            let text = try Self.source(path)
            for needle in ["NSLog(", "print(", "debugPrint(", "os_log", "Logger(", "dump(", "fputs(", "FileHandle.standardError"] {
                #expect(!text.contains(needle), "\(path) contains \(needle)")
            }
        }
    }

    @Test func theTypedFieldIsNeverStoredAndTheLearningSwitchGuardsWhatIs() throws {
        let service = try Self.source("Sources/PortKit/Services/CommandBar/CommandBarService.swift")
        #expect(service.contains("guard PortCommandBarLearning.isEnabled() else { return }"))
        // What was typed is remembered in memory only (promise of the upstream bar, kept).
        #expect(service.contains("lastQuery = query"))
        #expect(!service.contains("defaults.set(lastQuery") && !service.contains("set(query,") && !service.contains("set(lastQuery"))
        PortHostFixture.isolated { defaults in
            #expect(PortCommandBarLearning.isEnabled(in: defaults), "on until the person turns it off")
            defaults.set(false, forKey: PortCommandBarLearning.key)
            #expect(!PortCommandBarLearning.isEnabled(in: defaults))
        }
    }

    // MARK: The panel never steals focus and always closes

    @Test func thePanelNeverActivatesTheAppAndClosesOnEscapeAClickOutsideAndAnAppSwitch() throws {
        let service = try Self.source("Sources/PortKit/Services/CommandBar/CommandBarService.swift")
        #expect(service.contains("styleMask: [.borderless, .nonactivatingPanel]"), "the app in front keeps the keyboard focus owner")
        #expect(service.contains("panel.hidesOnDeactivate = false"))
        // Mac Island comes forward only to show the confirmation of a destructive row the person just chose (force quit,
        // kill a process or all of its kind, kill a tree): never from opening, typing or any other row.
        let lines = service.split(separator: "\n", omittingEmptySubsequences: false)
        var activations = 0
        for (index, line) in lines.enumerated() where line.contains("NSApp.activate") {
            activations += 1
            let owner = lines[..<index].last { $0.contains("private func ") || $0.contains("    func ") }
            #expect(owner?.contains("func confirm") == true, "line \(index + 1) is inside \(owner ?? "?")")
        }
        #expect(activations == 4)
        #expect(service.contains("NSEvent.addGlobalMonitorForEvents(matching: mouseEvents)"), "a click in another app")
        #expect(service.contains("NSEvent.addLocalMonitorForEvents(matching: mouseEvents)"), "a click in our own windows")
        #expect(service.contains("NSWorkspace.didActivateApplicationNotification"), "another app came forward")
        #expect(service.contains("keyCode == kVK_Escape") || service.contains("kVK_Escape"), "Escape steps back or closes")
        let view = try Self.source("Sources/PortKit/UI/CommandBar/CommandBarView.swift")
        #expect(!view.contains("NSApp.activate"))
    }

    @Test func theBarOpensInItsOwnWindowBecauseVorssaintsIslandStaysAsleep() {
        PortHostFixture.isolated { defaults in
            defaults.set(true, forKey: DefaultsKey.notchCommandBar)
            defaults.set("island", forKey: DefaultsKey.notchCommandBarStyle)
            defaults.set(true, forKey: DefaultsKey.notchEnabled)
            PortHost.availability = { _ in true }
            #expect(PortHost.vorssaintIslandEnabled == false, "Mac Island has one island")
            #expect(NotchSupport.isEnabled() == false)
            #expect(NotchMascotSupport.commandBarStyle() == nil, "so the bar never asks the dormant island for a host or a drop")
            #expect(NotchSupport.routes(.volume) == false, "the volume row falls back to the floating HUD")
            #expect(NotchMascotSupport.reacts() == false)
        }
    }

    @Test func theBarWindowIsOnlyBuiltOnceTheFeatureIsAvailable() throws {
        let service = try Self.source("Sources/PortKit/Services/CommandBar/CommandBarService.swift")
        #expect(service.contains("guard AppFeature.commandBar.isAvailable else { return }"), "show() refuses a held-down bar")
        #expect(service.contains("guard AppFeature.commandBar.isAvailable, let self else { return }"))
        #expect(service.contains("let wanted = AppFeature.commandBar.isAvailable ? rowShortcuts : [:]"), "no row shortcut while down")
        PortHostFixture.isolated { defaults in
            Defaults.register(in: defaults)
            #expect(defaults.bool(forKey: DefaultsKey.commandBarShortcutEnabled) == false, "ported default: off until migrated or chosen")
            #expect(defaults.bool(forKey: DefaultsKey.commandBarASCIILayoutEnabled) == false)
            #expect(defaults.bool(forKey: DefaultsKey.commandBarCompactMode) == false)
            #expect((defaults.string(forKey: DefaultsKey.commandBarFileScopes) ?? "") == "", "no folder is searched until named")
        }
    }

    // MARK: Permissions are read, never asked at start

    @Test func theSourcesThatNeedAccessibilityCheckItThemselvesAndStartNeverPrompts() throws {
        let menus = try Self.source("Sources/PortKit/Services/CommandBar/CommandBarMenus.swift")
        #expect(menus.contains("guard AXIsProcessTrusted() else { return [] }"))
        let selection = try Self.source("Sources/PortKit/Services/CommandBar/CommandBarSelection.swift")
        #expect(selection.contains("guard AXIsProcessTrusted() else { return (\"\", \"\", false) }"))
        let reader = try Self.source("Sources/PortKit/Services/SelectedTextReader.swift")
        #expect(reader.contains("guard AXIsProcessTrusted() else { return nil }"))
        let service = try Self.source("Sources/PortKit/Services/CommandBar/CommandBarService.swift")
        #expect(service.contains("guard Permissions.shared.accessibility,"), "menus load only with the grant")
        #expect(service.contains("guard isEnabled(.selection), Permissions.shared.accessibility else { return }"))
        // The one place that points the person at the pane is a row they ran (a paste or a typed snippet).
        let prompts = service.components(separatedBy: "requestAccessibility()").count - 1
        #expect(prompts == 1, "only the paste of a history row")
        let lane = try Self.source("Sources/PortKit/Bridge/CommandBar.swift")
        #expect(!lane.contains("requestAccessibility") && !lane.contains("AXIsProcessTrustedWithOptions"))
    }

    @Test func theSpotlightQueryOfAFileSearchCannotBeBrokenOutOf() {
        let expression = CommandBarFileSearchSupport.expression(for: "report\" || kMDItemFSName == \"*")
        let text = expression ?? ""
        #expect(!text.isEmpty)
        // One clause per typed word (five), each a quoted value with no bare quote or backslash inside: a word cannot
        // close its clause and open another.
        let clauses = text.components(separatedBy: " && ")
        #expect(clauses.count == 5, "\(clauses.count) clauses")
        let clause = try? NSRegularExpression(pattern: #"^kMDItemFSName == "\*(?:[^"\\]|\\.)*\*"cd$"#)
        for part in clauses {
            #expect(clause?.firstMatch(in: part, range: NSRange(part.startIndex..., in: part)) != nil, "\(part)")
        }
        #expect(text.contains("report\\\""), "the typed quote is escaped")
        #expect(CommandBarFileSearchSupport.expression(for: "   ") == nil)
    }

    // MARK: Helpers

    static func source(_ path: String) throws -> String {
        try String(contentsOf: PortSourceScrubTests.repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    /// Every Swift file of the command bar: its services, its views and the lane's bridge.
    static func commandBarFiles() throws -> [String] {
        var files: [String] = []
        for dir in ["Sources/PortKit/Services/CommandBar", "Sources/PortKit/UI/CommandBar"] {
            let names = try FileManager.default.contentsOfDirectory(
                atPath: PortSourceScrubTests.repoRoot.appendingPathComponent(dir).path)
            files += names.filter { $0.hasSuffix(".swift") }.sorted().map { "\(dir)/\($0)" }
        }
        files.append("Sources/PortKit/Bridge/CommandBar.swift")
        return files
    }
}
