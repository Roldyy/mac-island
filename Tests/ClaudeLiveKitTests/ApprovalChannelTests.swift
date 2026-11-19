import ClaudeApproveCore
import Darwin
import Foundation
import Testing

/// The hook <-> island protocol. The test plays the island: it reads the pending request, hashes it and writes (or forges) a decision.
/// Synthetic data only.
@Suite struct ApprovalChannelTests {
    final class Rig: @unchecked Sendable {
        let base: URL
        let channel: ApprovalChannel
        let home: String
        let cwd: String
        let sid = "64f70211-73af-4c0b-a0aa-a23d92ced74b"

        init(alive: Bool = true) {
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mis-appr-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            base = URL(fileURLWithPath: String(cString: realpath(tmp.path, nil)!))
            home = base.path + "/home"
            cwd = base.path + "/proj"
            try? FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(atPath: cwd, withIntermediateDirectories: true)
            try? "a".write(toFile: cwd + "/a.py", atomically: true, encoding: .utf8)
            channel = ApprovalChannel(root: base.appendingPathComponent("channel"))
            channel.prepare()
            if alive { touchAlive() }
        }
        deinit { try? FileManager.default.removeItem(at: base) }

        func touchAlive(secondsAgo: TimeInterval = 0) {
            PrivateFile.write(Data("1".utf8), to: channel.alive)
            let t = time(nil) - Int(secondsAgo)
            var times = [timeval(tv_sec: t, tv_usec: 0), timeval(tv_sec: t, tv_usec: 0)]
            utimes(channel.alive.path, &times)
        }

        func payload(tool: String = "Read", input: [String: Any]? = nil, event: String = "PermissionRequest") -> Data {
            let object: [String: Any] = [
                "hook_event_name": event, "session_id": sid, "cwd": cwd, "permission_mode": "default",
                "tool_name": tool, "tool_input": input ?? ["file_path": cwd + "/a.py"],
            ]
            return try! JSONSerialization.data(withJSONObject: object)
        }

        var config: ApprovalHookRunner.Config {
            var c = ApprovalHookRunner.Config()
            c.waitSeconds = 3; c.tick = 0.02
            return c
        }

        func pendingFiles() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: channel.pending.path)) ?? []).filter { !$0.hasPrefix(".") }
        }
        func decisionFiles() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: channel.decisions.path)) ?? [])
        }

        /// Plays the island on a thread: waits for the pending file, then calls `act(nonce, request, hash)`.
        func playIsland(timeout: TimeInterval = 2, _ act: @escaping @Sendable (_ nonce: String, _ request: String, _ hash: String) -> Void) -> Thread {
            let finished = DispatchSemaphore(value: 0)
            let thread = Thread { [self] in
                defer { finished.signal() }
                let deadline = Date().addingTimeInterval(timeout)
                while Date() < deadline {
                    if let name = pendingFiles().first,
                       let data = try? Data(contentsOf: channel.pending.appendingPathComponent(name)),
                       let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let nonce = object["nonce"] as? String, let request = object["request"] as? String {
                        act(nonce, request, ApprovalHash.sha256Hex(request))
                        return
                    }
                    Thread.sleep(forTimeInterval: 0.01)
                }
            }
            thread.start()
            _ = finished  // the thread signals when done; callers wait through the hook call itself
            return thread
        }

        func decide(_ behavior: ApprovalBehavior, nonce: String, hash: String) {
            ApprovalDecisionFile.write(behavior: behavior, nonce: nonce, hash: hash,
                                       nowMs: Int64(Date().timeIntervalSince1970 * 1000), channel: channel)
        }
    }

    private func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    // MARK: answers

    @Test func allowDecisionPrintsTheAllowAnswer() {
        let rig = Rig()
        _ = rig.playIsland { nonce, _, hash in rig.decide(.allow, nonce: nonce, hash: hash) }
        let out = ApprovalHookRunner.run(input: rig.payload(), channel: rig.channel, home: rig.home, config: rig.config)
        #expect(text(out) == #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#)
        #expect(rig.pendingFiles().isEmpty)
        #expect(rig.decisionFiles().isEmpty)
    }

    @Test func denyDecisionPrintsTheDenyAnswer() {
        let rig = Rig()
        _ = rig.playIsland { nonce, _, hash in rig.decide(.deny, nonce: nonce, hash: hash) }
        let out = ApprovalHookRunner.run(input: rig.payload(), channel: rig.channel, home: rig.home, config: rig.config)
        let object = try? JSONSerialization.jsonObject(with: out) as? [String: Any]
        let decision = ((object?["hookSpecificOutput"] as? [String: Any])?["decision"]) as? [String: Any]
        #expect(decision?["behavior"] as? String == "deny")
        #expect(!text(out).contains("updatedInput"))
        #expect(!text(out).contains("updatedPermissions"))
    }

    @Test func denyIsHonouredEvenForADenyOnlyRequest() {
        let rig = Rig()
        let input: [String: Any] = ["command": "rm -rf /tmp/x"]   // not a read-only verb: deny-only tier
        _ = rig.playIsland { nonce, _, hash in rig.decide(.deny, nonce: nonce, hash: hash) }
        let out = ApprovalHookRunner.run(input: rig.payload(tool: "Bash", input: input), channel: rig.channel, home: rig.home, config: rig.config)
        #expect(text(out).contains(#""behavior":"deny""#))
    }

    // MARK: what the pending file holds

    @Test func pendingFileIsOwnerOnlyAndHoldsNoFullPath() {
        let rig = Rig()
        final class Seen: @unchecked Sendable { var mode: Int = 0; var text = ""; var nonce = "" }
        let seen = Seen()
        _ = rig.playIsland { nonce, _, hash in
            let name = rig.pendingFiles().first ?? ""
            var st = stat()
            if lstat(rig.channel.pending.appendingPathComponent(name).path, &st) == 0 { seen.mode = Int(st.st_mode & 0o777) }
            seen.text = (try? String(contentsOf: rig.channel.pending.appendingPathComponent(name), encoding: .utf8)) ?? ""
            seen.nonce = nonce
            rig.decide(.allow, nonce: nonce, hash: hash)
        }
        _ = ApprovalHookRunner.run(input: rig.payload(), channel: rig.channel, home: rig.home, config: rig.config)
        #expect(seen.mode == 0o600)
        #expect(seen.nonce.count == 32)
        #expect(seen.text.contains(#""folderName":"proj""#))
        // The request itself names a file of the chat (that is what Harold approves); the CHAT's own path stays out of the record.
        #expect(!seen.text.contains(#""cwd""#))
        #expect(seen.text.contains(#""tier":"allow""#))
    }

    // MARK: answers that must be ignored (the hook prints nothing, the native dialog decides)

    private func ignored(_ name: String, tool: String = "Read", input: [String: Any]? = nil,
                         forge: @escaping @Sendable (Rig, String, String) -> Void) {
        let rig = Rig()
        var config = rig.config
        config.waitSeconds = 0.6
        _ = rig.playIsland { nonce, _, hash in forge(rig, nonce, hash) }
        let out = ApprovalHookRunner.run(input: rig.payload(tool: tool, input: input), channel: rig.channel, home: rig.home, config: config)
        #expect(out.isEmpty, "\(name): the hook must print nothing")
        #expect(rig.pendingFiles().isEmpty, "\(name): pending file removed")
        #expect(rig.decisionFiles().isEmpty, "\(name): forged decision removed")
    }

    @Test func wrongHashIsIgnored() {
        ignored("wrong hash") { rig, nonce, _ in rig.decide(.allow, nonce: nonce, hash: String(repeating: "0", count: 64)) }
    }

    @Test func wrongNonceInsideTheFileIsIgnored() {
        ignored("wrong nonce") { rig, nonce, hash in
            let body = #"{"nonce":"\#(String(repeating: "a", count: 32))","hash":"\#(hash)","behavior":"allow","ts":\#(Int64(Date().timeIntervalSince1970 * 1000))}"#
            PrivateFile.write(Data(body.utf8), to: rig.channel.decisions.appendingPathComponent(nonce + ".json"))
        }
    }

    @Test func decisionThatIsNotOwnerOnlyIsIgnored() {
        ignored("mode 644") { rig, nonce, hash in
            // Born 0644: written aside, chmod'ed, then renamed in, so the hook never sees a valid 0600 file first.
            let body = #"{"nonce":"\#(nonce)","hash":"\#(hash)","behavior":"allow","ts":\#(Int64(Date().timeIntervalSince1970 * 1000))}"#
            let aside = rig.base.appendingPathComponent("aside.json")
            try? Data(body.utf8).write(to: aside)
            chmod(aside.path, 0o644)
            rename(aside.path, rig.channel.decisions.appendingPathComponent(nonce + ".json").path)
        }
    }

    @Test func aRequestTooBigForTheRecordIsNeverWaitedFor() {
        // Quote-heavy text is escaped twice in the record: a request under the request cap can still overflow the record.
        let rig = Rig()
        let lines = String(repeating: "\"a\",\"b\"\n", count: 3700)
        let started = Date()
        let out = ApprovalHookRunner.run(input: rig.payload(tool: "Write", input: ["file_path": rig.cwd + "/export.csv", "content": lines]),
                                         channel: rig.channel, home: rig.home, config: rig.config)
        #expect(out.isEmpty)
        #expect(rig.pendingFiles().isEmpty)
        #expect(Date().timeIntervalSince(started) < 1)
    }

    @Test func decisionThatIsASymlinkIsIgnored() {
        ignored("symlink") { rig, nonce, hash in
            let real = rig.base.appendingPathComponent("real.json")
            let body = #"{"nonce":"\#(nonce)","hash":"\#(hash)","behavior":"allow","ts":\#(Int64(Date().timeIntervalSince1970 * 1000))}"#
            PrivateFile.write(Data(body.utf8), to: real)
            symlink(real.path, rig.channel.decisions.appendingPathComponent(nonce + ".json").path)
        }
    }

    @Test func staleDecisionIsIgnored() {
        ignored("stale") { rig, nonce, hash in
            let ts = Int64(Date().timeIntervalSince1970 * 1000) - 60_000
            ApprovalDecisionFile.write(behavior: .allow, nonce: nonce, hash: hash, nowMs: ts, channel: rig.channel)
        }
    }

    @Test func malformedDecisionIsIgnored() {
        ignored("not json") { rig, nonce, _ in
            PrivateFile.write(Data("not json".utf8), to: rig.channel.decisions.appendingPathComponent(nonce + ".json"))
        }
    }

    @Test func allowIsRefusedForADenyOnlyRequest() {
        // The hook enforces its own tier whatever the decision file says.
        ignored("allow on deny-only", tool: "Bash", input: ["command": "rm -rf /tmp/x"]) { rig, nonce, hash in
            rig.decide(.allow, nonce: nonce, hash: hash)
        }
    }

    // MARK: no island, no wait

    @Test func noHeartbeatMeansNoWaitAndNoPendingFile() {
        let rig = Rig(alive: false)
        let started = Date()
        let out = ApprovalHookRunner.run(input: rig.payload(), channel: rig.channel, home: rig.home, config: rig.config)
        #expect(out.isEmpty)
        #expect(Date().timeIntervalSince(started) < 0.5)
        #expect(rig.pendingFiles().isEmpty)
    }

    @Test func staleHeartbeatMeansNoWait() {
        let rig = Rig(alive: false)
        rig.touchAlive(secondsAgo: 60)
        let started = Date()
        let out = ApprovalHookRunner.run(input: rig.payload(), channel: rig.channel, home: rig.home, config: rig.config)
        #expect(out.isEmpty)
        #expect(Date().timeIntervalSince(started) < 0.5)
        #expect(rig.pendingFiles().isEmpty)
    }

    @Test func heartbeatThatIsASymlinkIsNotTrusted() {
        let rig = Rig(alive: false)
        let real = rig.base.appendingPathComponent("alive-real")
        PrivateFile.write(Data("1".utf8), to: real)
        symlink(real.path, rig.channel.alive.path)
        #expect(!rig.channel.isAlive())
    }

    // MARK: requests that never enter the channel

    @Test func refusedToolsNeverCreateAPendingFile() {
        for tool in ["AskUserQuestion", "ExitPlanMode", "WebFetch"] {
            let rig = Rig()
            let started = Date()
            let out = ApprovalHookRunner.run(input: rig.payload(tool: tool, input: ["url": "https://example.com"]),
                                             channel: rig.channel, home: rig.home, config: rig.config)
            #expect(out.isEmpty, "\(tool)")
            #expect(rig.pendingFiles().isEmpty, "\(tool)")
            #expect(Date().timeIntervalSince(started) < 0.5, "\(tool)")
        }
    }

    @Test func otherEventsAndGarbageAreIgnored() {
        let rig = Rig()
        #expect(ApprovalHookRunner.run(input: rig.payload(event: "Notification"), channel: rig.channel, home: rig.home, config: rig.config).isEmpty)
        #expect(ApprovalHookRunner.run(input: Data("nope".utf8), channel: rig.channel, home: rig.home, config: rig.config).isEmpty)
        #expect(ApprovalHookRunner.run(input: Data(), channel: rig.channel, home: rig.home, config: rig.config).isEmpty)
        #expect(rig.pendingFiles().isEmpty)
    }

    // MARK: end of the wait

    @Test func timeoutPrintsNothingAndCleansUp() {
        let rig = Rig()
        var config = rig.config
        config.waitSeconds = 0.3
        let out = ApprovalHookRunner.run(input: rig.payload(), channel: rig.channel, home: rig.home, config: config)
        #expect(out.isEmpty)
        #expect(rig.pendingFiles().isEmpty)
    }

    @Test func cancellationStopsTheWaitAndCleansUp() {
        let rig = Rig()
        var config = rig.config
        config.waitSeconds = 30
        let started = Date()
        let out = ApprovalHookRunner.run(input: rig.payload(), channel: rig.channel, home: rig.home, config: config,
                                         cancelled: { Date().timeIntervalSince(started) > 0.2 })
        #expect(out.isEmpty)
        #expect(Date().timeIntervalSince(started) < 2)
        #expect(rig.pendingFiles().isEmpty)
    }

    @Test func noRequestTextSurvivesAnyOutcome() {
        let rig = Rig()
        let secret = "SECRET-COMMAND-TEXT"
        var config = rig.config
        config.waitSeconds = 0.3
        _ = ApprovalHookRunner.run(input: rig.payload(tool: "Bash", input: ["command": "ls \(secret)"]), channel: rig.channel,
                                   home: rig.home, config: config)
        let all = (FileManager.default.enumerator(atPath: rig.channel.root.path)?.allObjects as? [String]) ?? []
        for name in all {
            let path = rig.channel.root.appendingPathComponent(name).path
            if let content = try? String(contentsOfFile: path, encoding: .utf8) { #expect(!content.contains(secret), "\(name)") }
        }
    }
}
