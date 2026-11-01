import Foundation
@testable import DisplayFeature

/// A throwaway defaults suite whose persistent domain is removed when the handle is released.
final class TempDefaults {
    let suite: String
    let defaults: UserDefaults
    init() {
        suite = NSTemporaryDirectory() + "display-test-\(UUID().uuidString)"  // temp path: no file in ~/Library/Preferences
        defaults = UserDefaults(suiteName: suite)!
    }
    deinit {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(atPath: suite + ".plist")
    }
}

func app(_ pid: Int32, _ bundle: String? = nil, regular: Bool = true, front: Bool = false,
         audio: Bool = false, windows: Int = 0) -> AppSnapshot {
    AppSnapshot(pid: pid, bundleID: bundle ?? "test.app\(pid)", name: "App\(pid)", isRegular: regular,
                isFrontmost: front, isPlayingAudio: audio, windowCount: windows)
}

let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }
