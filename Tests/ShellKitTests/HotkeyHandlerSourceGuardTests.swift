import Foundation
import Testing

/// Every Carbon handler for `kEventHotKeyPressed` in the app sees every hotkey press. One that answers `noErr` without
/// reading the `EventHotKeyID` hides all the others' shortcuts (it did: Keep Awake swallowed plain paste). This reads the
/// sources and fails for a file that installs such a handler without ever reading the id.
@Suite struct HotkeyHandlerSourceGuardTests {
    @Test func everyHotkeyHandlerReadsTheEventHotKeyID() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let walker = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var checked = 0
        var offenders: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  text.contains("InstallEventHandler"), text.contains("kEventHotKeyPressed") else { continue }
            checked += 1
            if !text.contains("typeEventHotKeyID") { offenders.append(url.lastPathComponent) }
        }
        #expect(checked >= 8, "the scan found only \(checked) files: the path logic is wrong")
        #expect(offenders.isEmpty, "handler never reads the EventHotKeyID: \(offenders)")
    }
}
