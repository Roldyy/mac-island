import Foundation
@testable import DisplayFeature

/// A throwaway defaults suite whose persistent domain is removed when the handle is released.
final class TempDefaults {
    let suite: String
    let defaults: UserDefaults
    init() {
        suite = "display-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    deinit {
        defaults.removePersistentDomain(forName: suite)
        // cfprefsd may flush the plist after the removal: make sure no file stays behind.
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(suite).plist")
        try? FileManager.default.removeItem(at: file)
    }
}

/// Scripted brightness backend: records every write, never touches a real display.
final class FakeBrightnessBackend: BrightnessBackend, @unchecked Sendable {
    var level: Float?
    var writeSucceeds = true
    private(set) var writes: [Float] = []
    init(level: Float?) { self.level = level }
    func read() -> Float? { level }
    func write(_ value: Float) -> Bool {
        writes.append(value)
        guard writeSucceeds else { return false }
        level = value
        return true
    }
}

func app(_ pid: Int32, _ bundle: String? = nil, regular: Bool = true, front: Bool = false,
         audio: Bool = false, windows: Int = 0) -> AppSnapshot {
    AppSnapshot(pid: pid, bundleID: bundle ?? "test.app\(pid)", name: "App\(pid)", isRegular: regular,
                isFrontmost: front, isPlayingAudio: audio, windowCount: windows)
}

let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }
