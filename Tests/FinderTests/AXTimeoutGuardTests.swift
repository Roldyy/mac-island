import Foundation
import Testing

/// A messaging timeout set on the system-wide Accessibility element applies to the whole process
/// (AXUIElement.h), so every other AX read of the app (the Dock lane's included) would be cut off.
/// There is no way to run Accessibility in a unit test, so this guards the source text: no file of the
/// Finder or Dock lane may pass the system-wide element (inline or through a variable) to
/// `AXUIElementSetMessagingTimeout`.
@Suite struct AXTimeoutGuardTests {
    static func sourceFiles() -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return ["Finder", "Dock"].flatMap { lane -> [URL] in
            let dir = root.appendingPathComponent("Sources/Features/\(lane)")
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            return names.filter { $0.hasSuffix(".swift") }.map { dir.appendingPathComponent($0) }
        }
    }

    /// The names a file binds to the system-wide element, plus the call itself.
    static func systemWideNames(in text: String) -> [String] {
        var names = ["AXUIElementCreateSystemWide"]
        let bind = try! NSRegularExpression(pattern: #"(?:let|var)\s+(\w+)\s*(?::[^=]+)?=\s*AXUIElementCreateSystemWide\(\)"#)
        for m in bind.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let r = Range(m.range(at: 1), in: text) { names.append(String(text[r])) }
        }
        return names
    }
    static func timeoutOnSystemWide(_ text: String) -> Bool {
        systemWideNames(in: text).contains { text.contains("AXUIElementSetMessagingTimeout(\($0)") }
    }

    @Test func detectorSeesAnInlineAndAVariableCall() {
        #expect(Self.timeoutOnSystemWide("let system = AXUIElementCreateSystemWide()\nAXUIElementSetMessagingTimeout(system, 0.05)"))
        #expect(Self.timeoutOnSystemWide("AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1)"))
        #expect(!Self.timeoutOnSystemWide("let app = AXUIElementCreateApplication(1)\nAXUIElementSetMessagingTimeout(app, 0.05)\nlet s = AXUIElementCreateSystemWide()"))
    }
    @Test func noFileSetsATimeoutOnTheSystemWideElement() throws {
        let files = Self.sourceFiles()
        #expect(files.count > 20)   // the scan found the lanes
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!Self.timeoutOnSystemWide(text), "\(file.lastPathComponent) sets a timeout on the system-wide element")
        }
    }
    @Test func finderQueriesItsOwnApplicationElementWithItsOwnTimeout() throws {
        let file = Self.sourceFiles().first { $0.lastPathComponent == "FinderEnvironment.swift" }
        let text = try String(contentsOf: #require(file), encoding: .utf8)
        #expect(text.contains("AXUIElementCreateApplication(finderPID)"))
    }
}
