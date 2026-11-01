import Foundation
import Testing
@testable import PortKit

/// Fixes of the W0 security audit (patch 1750): the Finder selection is a list, never a split string; the Now
/// Playing child gets its own environment and taint mode; the kill list protects Mac Island's own processes.
/// Fakes and pure functions only: no Finder, no perl child of the adapter, nothing is killed.
@Suite struct SecurityAuditFixesTests {
    // MARK: Finder selection

    @Test func aNameWithALineBreakNeverBecomesASecondItem() {
        let urls = FinderBridge.selectionURLs(fromPaths: ["/Users/me/a\n/etc/passwd"])
        #expect(urls.isEmpty, "one element holding a line break is rejected, not split")
    }

    @Test(arguments: ["\n", "\r", "\r\n", "\u{0B}", "\u{0C}", "\u{85}", "\u{2028}", "\u{2029}", "\u{0}"])
    func everyNewlineClassCharacterRejectsThePath(_ separator: String) {
        let hostile = "/Users/me/a" + separator + "/etc/passwd"
        #expect(!FinderBridge.isSafeSelectionPath(hostile))
        #expect(FinderBridge.selectionURLs(fromPaths: [hostile, "/Users/me/ok.txt"]).map(\.path) == ["/Users/me/ok.txt"],
                "only the offending item goes, the others stay")
    }

    @Test func plainAbsolutePathsKeepTheirOrderAndRelativeOnesAreRejected() {
        let urls = FinderBridge.selectionURLs(fromPaths: ["/a/b c.txt", "relative/x", "", "/a/é ü.txt", "/a/dir/"])
        #expect(urls.map(\.lastPathComponent) == ["b c.txt", "é ü.txt", "dir"])
    }

    @Test func theSelectionScriptReturnsAListAndNothingSplitsOnNewlines() throws {
        let source = try String(
            contentsOf: PortSourceScrubTests.repoRoot.appendingPathComponent("Sources/PortKit/Services/Finder/FinderCutPaste.swift"),
            encoding: .utf8)
        #expect(source.contains("set end of out to (POSIX path of (f as alias))"))
        #expect(!source.contains("& linefeed"))
        #expect(!source.contains("split(whereSeparator: \\.isNewline)"))
        #expect(!source.contains("FinderBridge.move("), "no hand-over of refused items to Finder (administrator prompt)")
    }

    @Test func refusedItemsAreReportedAsFailedAndLeftInPlace() {
        let refused = [URL(fileURLWithPath: "/Library/x"), URL(fileURLWithPath: "/Library/y")]
        let result = CutPastePrivilegeSupport.leaveInPlace(refused)
        #expect(result.moved == 0 && result.failed == 2 && result.stillCut.isEmpty)
        let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        #expect(CutPastePrivilegeSupport.needsPrivileges(denied), "the refusal is still recognised, it is just never escalated")
    }

    // MARK: Now Playing child

    @Test func theChildEnvironmentIsBuiltFromScratch() {
        let hostile: [String: String] = [
            "PERL5OPT": "-MEvil", "PERL5LIB": "/tmp/evil", "PERL5DB": "x", "PERLLIB": "/tmp/evil",
            "DYLD_INSERT_LIBRARIES": "/tmp/evil.dylib", "DYLD_LIBRARY_PATH": "/tmp", "DYLD_FRAMEWORK_PATH": "/tmp",
            "LD_PRELOAD": "x", "GITHUB_TOKEN": "secret", "PATH": "/tmp/evil:/usr/bin",
            "HOME": "/Users/me", "TMPDIR": "/var/folders/x/T/", "LANG": "fr_BE.UTF-8",
        ]
        let environment = MediaRemoteAdapterLocator.childEnvironment(from: hostile)
        #expect(Set(environment.keys) == ["PATH", "HOME", "TMPDIR", "LANG"])
        #expect(environment["PATH"] == "/usr/bin:/bin")
        #expect(environment["HOME"] == "/Users/me")
        #expect(environment["TMPDIR"] == "/var/folders/x/T/")
        #expect(environment["LANG"] == "fr_BE.UTF-8")
        for key in environment.keys {
            #expect(!key.hasPrefix("PERL") && !key.hasPrefix("DYLD_") && !key.hasPrefix("LD_"), "\(key) was forwarded")
        }
    }

    @Test func theChildEnvironmentFallsBackWhenTheAppHasNone() {
        let environment = MediaRemoteAdapterLocator.childEnvironment(from: [:])
        #expect(environment["PATH"] == "/usr/bin:/bin")
        #expect(environment["HOME"] == NSHomeDirectory())
        #expect(environment["TMPDIR"] == NSTemporaryDirectory())
        #expect(environment["LANG"] == "en_US.UTF-8")
        #expect(MediaRemoteAdapterLocator.childEnvironment(from: ["HOME": ""])["HOME"] == NSHomeDirectory())
    }

    @Test func perlRunsInTaintModeWithNoIncludeFlag() {
        let arguments = MediaRemoteAdapterLocator.perlArguments(adapter: ["/app/now-playing.pl", "/app/lib.dylib"], mode: "watch")
        #expect(arguments == ["-T", "/app/now-playing.pl", "/app/lib.dylib", "watch"])
        #expect(!arguments.contains { $0.hasPrefix("-I") })
    }

    @Test func aRealPerlWithThatSetupIgnoresPERL5OPTAndPERL5LIB() throws {
        // Taint mode makes perl drop PERL5OPT and PERL5LIB; the minimal environment never carries them anyway. Both are
        // checked on the real /usr/bin/perl with a one-liner (not the adapter): the guard is observable, not assumed.
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-T", "-e", "print join(q(,), sort keys %ENV), q(|), scalar(grep { $_ eq q(/tmp/evil-lib) } @INC)"]
        process.environment = MediaRemoteAdapterLocator.childEnvironment(from: ["PERL5OPT": "-Mstrict", "PERL5LIB": "/tmp/evil-lib", "HOME": "/h"])
            .merging(["PERL5LIB": "/tmp/evil-lib", "PERL5OPT": "-e1"], uniquingKeysWith: { _, new in new })
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 0, "perl -T accepts the arguments: \(text)")
        #expect(text.hasSuffix("|0"), "taint mode keeps PERL5LIB out of @INC even when forced into the environment: \(text)")
    }

    // MARK: Kill list

    @Test func theKillListProtectsMacIslandsOwnProcesses() {
        for name in ["MacIsland", "macisland", "Mac Island", "be.roldy.macisland.fanhelper", " MacIsland "] {
            #expect(KillProcessSupport.isProtected(pid: 4242, name: name), "\(name)")
        }
        #expect(KillProcessSupport.isProtected(pid: 4242, path: "/Applications/Mac Island.app/Contents/MacOS/MacIsland"))
        #expect(KillProcessSupport.isProtected(pid: 4242, path: "/Library/PrivilegedHelperTools/be.roldy.macisland.fanhelper"))
        #expect(!KillProcessSupport.isProtected(pid: 4242, name: "Safari", path: "/Applications/Safari.app/Contents/MacOS/Safari"))
    }
}
