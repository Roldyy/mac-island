import Foundation
@testable import CommandBarFeature

func makeTempDir(_ name: String = "CmdBarTest") -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Isolated defaults suite, emptied on creation. Synthetic keys only.
func makeDefaults() -> UserDefaults {
    let name = "be.roldy.macisland.tests.commandbar.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
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
