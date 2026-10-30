import Foundation
import Darwin
import Testing
@testable import TerminalFeature

@Suite struct ProcessTreeTests {
    @Test func matchesClaudeByName() {
        #expect(ProcessTree.isClaude(name: "claude", argvBasenames: []))
    }

    @Test func matchesRetitledBinary() {
        #expect(ProcessTree.isClaude(name: "2.1.301", argvBasenames: ["claude"]))
    }

    @Test func matchesNodeRunningClaude() {
        #expect(ProcessTree.isClaude(name: "node", argvBasenames: ["node", "claude"]))
    }

    @Test func rejectsOtherNodeAndShells() {
        #expect(!ProcessTree.isClaude(name: "node", argvBasenames: ["node", "vite"]))
        #expect(!ProcessTree.isClaude(name: "node", argvBasenames: []))
        #expect(!ProcessTree.isClaude(name: "zsh", argvBasenames: ["-zsh"]))
        #expect(!ProcessTree.isClaude(name: "claudette", argvBasenames: ["claudette"]))
    }

    @Test func parsesProcArgsBasenamesOnly() {
        var data = [UInt8](withUnsafeBytes(of: Int32(3).littleEndian) { Array($0) })
        data += Array("/usr/local/bin/node".utf8) + [0, 0, 0]
        data += Array("node".utf8) + [0]
        data += Array("/opt/lib/claude".utf8) + [0]
        data += Array("--secret-token=abc".utf8) + [0]
        data += Array("HOME=/Users/x".utf8) + [0]
        let names = ProcessTree.argvBasenames(fromProcArgs: data)
        #expect(names == ["node", "claude"])
    }

    @Test func parseHandlesGarbage() {
        #expect(ProcessTree.argvBasenames(fromProcArgs: []).isEmpty)
        #expect(ProcessTree.argvBasenames(fromProcArgs: [1, 0]).isEmpty)
    }

    @Test func argvBasenamesOfRealChild() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["5"]
        try child.run()
        defer { child.terminate() }
        #expect(ProcessTree.argvBasenames(of: child.processIdentifier) == ["sleep", "5"])
    }

    @Test func descendantsExcludeSelfAndFindChild() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["5"]
        try child.run()
        defer { child.terminate() }
        let found = ProcessTree.descendants(of: getpid())
        #expect(found.contains(child.processIdentifier))
        #expect(!found.contains(getpid()))
        #expect(!ProcessTree.containsClaude(below: getpid()))
    }
}
