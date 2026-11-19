import ClaudeApproveCore
import Darwin
import Foundation
import Testing

/// The tier rules, played against the shared cases file (106 cases, same rules as the rm-board hook they were ported from).
/// The disk is synthetic: a temp home with fake secrets and a temp project folder, nothing real.
@Suite struct ApprovalTierTests {
    struct Disk {
        let root: URL, home: String, cwd: String
        init() throws {
            let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mis-tier-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            // /var is a symlink to /private/var on macOS: work on the physical path, as the hook does.
            let physical = String(cString: realpath(base.path, nil)!)
            root = URL(fileURLWithPath: physical)
            home = physical + "/home"
            cwd = physical + "/proj"
            let fm = FileManager.default
            for dir in [home + "/.ssh", home + "/.aws", cwd + "/.claude", cwd + "/.git", cwd + "/.venv"] {
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }
            try "key".write(toFile: home + "/.ssh/id_rsa", atomically: true, encoding: .utf8)
            try "notes".write(toFile: home + "/notes.txt", atomically: true, encoding: .utf8)
            try "a".write(toFile: cwd + "/a.py", atomically: true, encoding: .utf8)
            try "x".write(toFile: cwd + "/.env", atomically: true, encoding: .utf8)
            try fm.createSymbolicLink(atPath: cwd + "/link.txt", withDestinationPath: home + "/.ssh/id_rsa")
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    private static func substitute(_ value: Any, cwd: String, home: String, long: String) -> Any {
        switch value {
        case let s as String:
            return s.replacingOccurrences(of: "{CWD}", with: cwd).replacingOccurrences(of: "{HOME}", with: home)
                .replacingOccurrences(of: "{LONG}", with: long)
        case let d as [String: Any]: return d.mapValues { substitute($0, cwd: cwd, home: home, long: long) }
        case let a as [Any]: return a.map { substitute($0, cwd: cwd, home: home, long: long) }
        default: return value
        }
    }

    private static func casesURL() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/approve-cases.json")
    }

    @Test func sharedCasesClassifyAsExpected() throws {
        let disk = try Disk()
        defer { disk.remove() }
        let raw = try Data(contentsOf: Self.casesURL())
        let cases = try #require(JSONSerialization.jsonObject(with: raw) as? [[String: Any]])
        #expect(cases.count == 106)
        let long = (0..<80).map { "line\($0)" }.joined(separator: "\n") + "\n"
        var wrong: [String] = []
        for item in cases {
            let name = item["name"] as? String ?? "?"
            let tool = item["tool"] as? String
            let input = Self.substitute(item["input"] ?? [:], cwd: disk.cwd, home: disk.home, long: long)
            let want = item["expect"] as? String
            let ctx = ApprovalContext.resolve(toolName: tool, toolInput: input, cwd: disk.cwd, home: disk.home)
            let got = ApprovalClassifier.classify(toolName: tool, toolInput: input, context: ctx)
            if got.tier.rawValue != want { wrong.append("\(name): got \(got.tier.rawValue) (\(got.why)), want \(want ?? "?")") }
        }
        #expect(wrong.isEmpty, "\(wrong.joined(separator: "\n"))")
    }

    @Test func aRequestThatDoesNotFitOneLineCannotBeAllowed() throws {
        let disk = try Disk()
        defer { disk.remove() }
        func tier(_ name: String) -> ApprovalTier {
            let input: [String: Any] = ["file_path": disk.cwd + "/" + name]
            let ctx = ApprovalContext.resolve(toolName: "Read", toolInput: input, cwd: disk.cwd, home: disk.home)
            return ApprovalClassifier.classify(toolName: "Read", toolInput: input, context: ctx).tier
        }
        #expect(tier("a.py") == .allow)
        // A path longer than the 200 characters the card shows is never allowed, however harmless it looks.
        #expect(tier(String(repeating: "x", count: 250) + ".py") == .denyOnly)
    }

    @Test func aLineBreakOfAnyKindMakesABashCommandDenyOnly() throws {
        let disk = try Disk()
        defer { disk.remove() }
        func tier(_ command: String) -> ApprovalTier {
            let input: [String: Any] = ["command": command]
            let ctx = ApprovalContext.resolve(toolName: "Bash", toolInput: input, cwd: disk.cwd, home: disk.home)
            return ApprovalClassifier.classify(toolName: "Bash", toolInput: input, context: ctx).tier
        }
        #expect(tier("cat a.py") == .allow)
        #expect(tier("cat a.py\nrm -rf src") == .denyOnly)
        #expect(tier("cat a.py\r\nrm -rf src") == .denyOnly)   // "\r\n" is ONE Character in Swift: judged on scalars
        #expect(tier("cat a.py\rrm -rf src") == .denyOnly)
        #expect(tier("cat a.py\trm") == .denyOnly)
    }

    @Test func aChangeWithACarriageReturnIsNotASingleLine() throws {
        let disk = try Disk()
        defer { disk.remove() }
        let input: [String: Any] = ["file_path": disk.cwd + "/a.py", "old_string": "a", "new_string": "b\r\nimport os"]
        let ctx = ApprovalContext.resolve(toolName: "Edit", toolInput: input, cwd: disk.cwd, home: disk.home)
        #expect(ApprovalClassifier.classify(toolName: "Edit", toolInput: input, context: ctx).tier == .denyOnly)
        let path: [String: Any] = ["file_path": disk.cwd + "/a.py\r\n"]
        let ctx2 = ApprovalContext.resolve(toolName: "Read", toolInput: path, cwd: disk.cwd, home: disk.home)
        #expect(ApprovalClassifier.classify(toolName: "Read", toolInput: path, context: ctx2).tier == .denyOnly)
    }

    @Test func aRelativeTargetIsResolvedInTheChatFolder() throws {
        let disk = try Disk()
        defer { disk.remove() }
        func tier(_ tool: String, _ input: [String: Any]) -> ApprovalTier {
            let ctx = ApprovalContext.resolve(toolName: tool, toolInput: input, cwd: disk.cwd, home: disk.home)
            return ApprovalClassifier.classify(toolName: tool, toolInput: input, context: ctx).tier
        }
        // A Grep over a folder can read a secret inside it: "." and "src" are folders of the chat, never allowed.
        try FileManager.default.createDirectory(atPath: disk.cwd + "/src", withIntermediateDirectories: true)
        #expect(tier("Grep", ["pattern": "API_KEY", "path": "."]) == .denyOnly)
        #expect(tier("Grep", ["pattern": "API_KEY", "path": "src"]) == .denyOnly)
        #expect(tier("Grep", ["pattern": "x", "path": "a.py"]) == .allow)
        #expect(tier("Read", ["file_path": ".env"]) == .denyOnly)
        #expect(tier("Read", ["file_path": "a.py"]) == .allow)
    }

    @Test func missingToolIsRefused() {
        let verdict = ApprovalClassifier.classify(toolName: nil, toolInput: [:], context: ApprovalContext(home: "/h"))
        #expect(verdict.tier == .refuse)
    }

    @Test func theIslandsOwnFolderIsNeverReachable() throws {
        let disk = try Disk()
        defer { disk.remove() }
        let input: [String: Any] = ["file_path": disk.home + "/Library/Application Support/be.roldy.macisland/claude-approvals/alive"]
        let ctx = ApprovalContext.resolve(toolName: "Read", toolInput: input, cwd: disk.cwd, home: disk.home)
        #expect(ApprovalClassifier.classify(toolName: "Read", toolInput: input, context: ctx).tier == .refuse)
    }
}
