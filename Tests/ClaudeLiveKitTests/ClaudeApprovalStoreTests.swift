import ClaudeApproveCore
import Darwin
import Foundation
import Testing
@testable import ClaudeLiveKit

@MainActor
@Suite struct ClaudeApprovalStoreTests {
    final class NoWatch: ClaudeFileWatching, @unchecked Sendable {
        func watch(_ paths: [String], onEvent: @escaping @Sendable () -> Void) {}
        func stop() {}
    }

    @MainActor struct Rig {
        let base: URL
        let channel: ApprovalChannel
        let store: ClaudeApprovalStore

        init(enabled: Bool = true) {
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mis-store-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            base = URL(fileURLWithPath: String(cString: realpath(tmp.path, nil)!))
            channel = ApprovalChannel(root: base.appendingPathComponent("ch"))
            store = ClaudeApprovalStore(channel: channel, watcher: NoWatch())
            store.isEnabled = { enabled }
        }

        func writePending(nonce: String = String(repeating: "a", count: 32), tool: String = "Bash",
                          input: [String: Any] = ["command": "ls"], tier: String = "allow", folder: String = "demo",
                          sid: String = "64f70211-73af-4c0b-a0aa-a23d92ced74b") {
            channel.prepare()
            let request = String(decoding: try! JSONSerialization.data(withJSONObject: ["tool_name": tool, "tool_input": input],
                                                                       options: [.sortedKeys]), as: UTF8.self)
            let record: [String: Any] = ["v": 1, "nonce": nonce, "sid": sid, "folderName": folder, "agent": "main", "mode": "",
                                         "ts": Int64(Date().timeIntervalSince1970 * 1000), "tier": tier, "why": "ok", "request": request]
            PrivateFile.write(try! JSONSerialization.data(withJSONObject: record), to: channel.pending.appendingPathComponent("\(sid).\(nonce).json"))
        }
        func decisionFiles() -> [String] { (try? FileManager.default.contentsOfDirectory(atPath: channel.decisions.path)) ?? [] }
        func cleanup() { try? FileManager.default.removeItem(at: base) }
    }

    @Test func aPendingFileBecomesARequestWithOneShortLine() {
        let rig = Rig(); defer { rig.cleanup() }
        rig.writePending(input: ["command": "ls -la"])
        rig.store.tick()
        let request = rig.store.requests.first
        #expect(rig.store.requests.count == 1)
        #expect(request?.tool == "Bash")
        #expect(request?.summary == "ls -la")
        #expect(request?.folderName == "demo")
        #expect(request?.canAllow == true)
    }

    @Test func theSummaryShowsEverythingTheRequestWouldDo() {
        let write = ClaudeApprovalStore.summarize(tool: "Write", input: ["file_path": "/p/setup.py", "content": "import os"])
        #expect(write.text == "/p/setup.py  ·  contenu : import os")
        #expect(write.complete)
        let edit = ClaudeApprovalStore.summarize(tool: "Edit", input: ["file_path": "/p/a.py", "old_string": "a", "new_string": "b"])
        #expect(edit.text == "/p/a.py  ·  avant : a  ·  après : b")
        let grep = ClaudeApprovalStore.summarize(tool: "Grep", input: ["pattern": "API_KEY", "path": "a.py"])
        #expect(grep.text == "a.py  ·  motif : API_KEY")
        #expect(ClaudeApprovalStore.summarize(tool: "Read", input: ["file_path": "/p/a.py"]).text == "/p/a.py")
        #expect(ClaudeApprovalStore.summarize(tool: "mcp__x__y", input: ["q": "1"]).text == "q : 1")
        #expect(ClaudeApprovalStore.summarize(tool: "Bash", input: ["command": "ls", "description": "x"]).text == "ls")
    }

    @Test func lineBreaksAndControlCharactersAreMadeVisible() {
        let line = ClaudeApprovalStore.summarize(tool: "Bash", input: ["command": "cat a\r\nrm -rf src\u{1}"])
        #expect(line.text == "cat a↵↵rm -rf src·".replacingOccurrences(of: "↵↵", with: "↵↵"))
        #expect(!line.text.unicodeScalars.contains { $0 == "\n" || $0 == "\r" })
    }

    @Test func aCutLineIsIncompleteAndNeverOffersAutoriser() throws {
        let long = String(repeating: "x", count: 400)
        let line = ClaudeApprovalStore.summarize(tool: "Bash", input: ["command": long])
        #expect(line.text.count == ClaudeApprovalStore.summaryLimit + 1)
        #expect(!line.complete)
        let rig = Rig(); defer { rig.cleanup() }
        // An `allow`-tier request whose line does not fit: the island must not offer Autoriser, and must refuse to send one.
        rig.writePending(tool: "Read", input: ["file_path": "/" + String(repeating: "y", count: 300)], tier: "allow")
        rig.store.tick()
        let request = try #require(rig.store.requests.first)
        #expect(!request.summaryComplete)
        #expect(!request.canAllow)
        #expect(!rig.store.decide(request, .allow))
        #expect(rig.decisionFiles().isEmpty)
    }

    @Test func aRefusedOrMalformedFileIsNotShown() {
        let rig = Rig(); defer { rig.cleanup() }
        rig.writePending(nonce: String(repeating: "b", count: 32), tier: "refuse")
        rig.writePending(nonce: String(repeating: "c", count: 32), tier: "bogus")
        rig.writePending(nonce: "short")
        PrivateFile.write(Data("not json".utf8), to: rig.channel.pending.appendingPathComponent("x.json"))
        rig.store.tick()
        #expect(rig.store.requests.isEmpty)
    }

    @Test func aStalePendingFileBelongsToADeadHookAndIsNotShown() {
        let rig = Rig(); defer { rig.cleanup() }
        rig.writePending()
        let file = rig.channel.pending.appendingPathComponent("64f70211-73af-4c0b-a0aa-a23d92ced74b.\(String(repeating: "a", count: 32)).json")
        let old = time(nil) - 60
        var times = [timeval(tv_sec: old, tv_usec: 0), timeval(tv_sec: old, tv_usec: 0)]
        utimes(file.path, &times)
        rig.store.tick()
        #expect(rig.store.requests.isEmpty)
    }

    @Test func switchedOffTouchesNothingAndShowsNothing() {
        let rig = Rig(enabled: false); defer { rig.cleanup() }
        rig.writePending()
        rig.store.tick()
        #expect(rig.store.requests.isEmpty)
        #expect(!rig.channel.isAlive())
    }

    @Test func enabledWritesTheHeartbeatAndSwitchingOffRemovesIt() {
        let rig = Rig(); defer { rig.cleanup() }
        rig.store.tick()
        #expect(rig.channel.isAlive())
        rig.store.isEnabled = { false }
        rig.store.tick()
        #expect(!rig.channel.isAlive())
    }

    @Test func releasingTheLastHolderRemovesTheHeartbeat() {
        let rig = Rig(); defer { rig.cleanup() }
        rig.store.acquire("a")
        #expect(rig.channel.isAlive())
        rig.store.release("a")
        #expect(!rig.channel.isAlive())
        #expect(rig.store.requests.isEmpty)
    }

    @Test func aNewRequestFiresTheSoundHookOnce() {
        let rig = Rig(); defer { rig.cleanup() }
        var count = 0
        rig.store.onNewRequest = { _ in count += 1 }
        rig.writePending()
        rig.store.tick(); rig.store.tick(); rig.store.rescan()
        #expect(count == 1)
    }

    @Test func allowWritesADecisionTheHookWouldAccept() throws {
        let rig = Rig(); defer { rig.cleanup() }
        rig.writePending()
        rig.store.tick()
        let request = try #require(rig.store.requests.first)
        #expect(rig.store.decide(request, .allow))
        #expect(rig.store.requests.isEmpty)
        let name = try #require(rig.decisionFiles().first)
        let result = ApprovalDecisionFile.validate(path: rig.channel.decisions.appendingPathComponent(name).path, nonce: request.id,
                                                   hash: request.hash, tier: request.tier,
                                                   startMs: Int64(Date().timeIntervalSince1970 * 1000) - 1000,
                                                   nowMs: Int64(Date().timeIntervalSince1970 * 1000))
        #expect(result == .success(.allow))
    }

    @Test func denyOnlyRequestCanBeDeniedButNeverAllowed() throws {
        let rig = Rig(); defer { rig.cleanup() }
        rig.writePending(input: ["command": "rm -rf /tmp/x"], tier: "deny-only")
        rig.store.tick()
        let request = try #require(rig.store.requests.first)
        #expect(!request.canAllow)
        #expect(!rig.store.decide(request, .allow))
        #expect(rig.decisionFiles().isEmpty)
        #expect(rig.store.decide(request, .deny))
    }

    @Test func nothingIsAnsweredWhileSwitchedOff() throws {
        let rig = Rig(); defer { rig.cleanup() }
        rig.writePending()
        rig.store.tick()
        let request = try #require(rig.store.requests.first)
        rig.store.isEnabled = { false }
        #expect(!rig.store.decide(request, .deny))
    }

    @Test func onlyTheVSCodeEntrypointNamesAHostApp() {
        #expect(ClaudeHostApp.bundleID(forEntrypoint: "claude-vscode") == "com.microsoft.VSCode")
        #expect(ClaudeHostApp.bundleID(forEntrypoint: "cli") == nil)
        #expect(ClaudeHostApp.bundleID(forEntrypoint: "../../evil") == nil)
        #expect(ClaudeHostApp.bundleID(forEntrypoint: nil) == nil)
    }
}
