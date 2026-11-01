import AppKit
import Foundation
import Testing
@testable import NowPlayingFeature

/// The generated AppleScript must COMPILE. Compiling sends no Apple Event and needs no permission, but it reads
/// the target app's dictionary, so a player that is not installed is skipped. A script that does not compile
/// fails at run time with error -2741 and the card then says 'erreur AppleScript (-2741)' (the variable name
/// `st` did exactly that: Spotify's dictionary rejects it, so the first status script never ran).
@Suite struct ScriptCompileTests {
    private func compileError(_ source: String) -> String? {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        if script?.compileAndReturnError(&error) == true { return nil }
        let number = (error?["NSAppleScriptErrorNumber"] as? Int).map(String.init) ?? "?"
        let message = (error?["NSAppleScriptErrorMessage"] as? String) ?? "no message"
        return "\(number): \(message)"
    }

    private func installed(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    @Test func spotifyStatusScriptCompiles() throws {
        try #require(installed(BundleIDs.spotify), "Spotify is not installed here")
        #expect(compileError(PlayerScripts.status(bundleID: BundleIDs.spotify)) == nil)
    }

    @Test func musicStatusScriptCompiles() throws {
        try #require(installed(BundleIDs.music), "Music is not installed here")
        #expect(compileError(PlayerScripts.status(bundleID: BundleIDs.music)) == nil)
    }

    @Test func commandScriptsCompileForSpotify() throws {
        try #require(installed(BundleIDs.spotify), "Spotify is not installed here")
        for command in [PlayerCommand.playPause, .next, .previous] {
            #expect(compileError(PlayerScripts.command(command, bundleID: BundleIDs.spotify)) == nil, "\(command)")
        }
    }

    @Test func noScriptNamesAVariableSt() {
        // The cheap guard that works without any player installed.
        for id in [BundleIDs.spotify, BundleIDs.music] {
            let source = PlayerScripts.status(bundleID: id)
            #expect(!source.contains("set st to"), "\(id)")
            #expect(!source.contains(" st &"), "\(id)")
        }
    }
}
