import CoreGraphics
import Testing
@testable import DisplayFeature

@Suite struct WindowCounterTests {
    private func win(pid: Int, layer: Int = 0, alpha: Double = 1, w: Double = 400, h: Double = 300) -> [String: Any] {
        ["kCGWindowOwnerPID": pid, "kCGWindowLayer": layer, "kCGWindowAlpha": alpha,
         "kCGWindowBounds": ["X": 0, "Y": 0, "Width": w, "Height": h]]
    }

    @Test func countsLayerZeroWindowsPerOwner() {
        let counts = WindowCounter.counts(from: [win(pid: 10), win(pid: 10), win(pid: 11)])
        #expect(counts[10] == 2)
        #expect(counts[11] == 1)
    }

    @Test func ignoresMenuBarLevelTransparentAndTinyWindows() {
        let counts = WindowCounter.counts(from: [
            win(pid: 10, layer: 25), win(pid: 10, alpha: 0), win(pid: 10, w: 1, h: 1),
        ])
        #expect(counts[10] == nil)
    }

    @Test func malformedEntriesAreSkipped() {
        let counts = WindowCounter.counts(from: [["kCGWindowLayer": 0], [:], win(pid: 12)])
        #expect(counts == [12: 1])
    }

    @Test func asksForAllWindowsNotOnlyOnScreenOnes() {
        var asked: CGWindowListOption?
        let counts = WindowCounter.currentCounts { options, _ in
            asked = options
            return [win(pid: 10)]
        }
        #expect(asked?.contains(.optionOnScreenOnly) == false)
        #expect(asked?.contains(.excludeDesktopElements) == true)
        #expect(counts[10] == 1)
    }

    @Test func offScreenWindowsAreCounted() {
        // Minimized, other Space, hidden app: the system flags them not on screen.
        var minimized = win(pid: 10)
        minimized["kCGWindowIsOnscreen"] = false
        #expect(WindowCounter.counts(from: [minimized])[10] == 1)
    }
}
