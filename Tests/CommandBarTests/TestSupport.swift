import Foundation
@testable import CommandBarFeature

func makeTempDir(_ name: String = "CmdBarTest") -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A throwaway defaults suite named by an absolute temp path, so its plist never lands in
/// ~/Library/Preferences. Domain and file are removed when the handle is released.
final class TempDefaults {
    let suite: String
    let defaults: UserDefaults
    init() {
        suite = FileManager.default.temporaryDirectory
            .appendingPathComponent("macisland-commandbar-test-\(UUID().uuidString)").path
        defaults = UserDefaults(suiteName: suite)!
    }
    deinit {
        defaults.removePersistentDomain(forName: suite)
        defaults.synchronize()
        try? FileManager.default.removeItem(atPath: suite + ".plist")
    }
}

/// Owned by a class-based suite (one instance per test): everything made here is cleaned in deinit.
final class DefaultsBag {
    private var handles: [TempDefaults] = []
    func makeDefaults() -> UserDefaults {
        let h = TempDefaults()
        handles.append(h)
        return h.defaults
    }
}

func result(_ id: String, _ title: String, kind: BarResult.Kind = .app,
            keywords: [String] = [], fixed: Double? = nil) -> BarResult {
    BarResult(id: id, title: title, kind: kind, action: .runCommand(id), keywords: keywords, fixedScore: fixed)
}

struct StubSource: ResultSource {
    let sourceID: String
    var isSlow = false
    var items: [BarResult]
    func results(for query: String) async -> [BarResult] { items }
}
