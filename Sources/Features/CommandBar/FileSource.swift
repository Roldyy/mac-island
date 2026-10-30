import Foundation

/// Files by name through Spotlight (`NSMetadataQuery`): no content indexing, at most 20 rows,
/// nothing for a query shorter than 3 characters. The query text only goes into the predicate
/// as a bound argument and is never logged.
@MainActor
struct FileSource: ResultSource {
    nonisolated let sourceID = "files"
    nonisolated var isSlow: Bool { true }
    nonisolated static let maxResults = 20
    nonisolated static let minQueryLength = 3
    nonisolated static let timeout: Duration = .milliseconds(1500)

    nonisolated static func isEligible(query: String) -> Bool {
        query.trimmingCharacters(in: .whitespaces).count >= minQueryLength
    }

    nonisolated static func isExcluded(path: String, home: String) -> Bool {
        if path.hasPrefix(home + "/Library/") { return true }
        let skipped: Set<String> = ["node_modules", ".Trash", "__pycache__"]
        return path.split(separator: "/").contains { $0.hasPrefix(".") || skipped.contains(String($0)) }
    }

    nonisolated static func makeResults(paths: [String], home: String) -> [BarResult] {
        var out: [BarResult] = []
        for p in paths where !isExcluded(path: p, home: home) {
            let url = URL(fileURLWithPath: p)
            out.append(BarResult(id: "file:\(p)", title: url.lastPathComponent,
                                 subtitle: (p as NSString).abbreviatingWithTildeInPath, kind: .file,
                                 action: .open(url), reveal: url))
            if out.count == maxResults { break }
        }
        return out
    }

    func results(for query: String) async -> [BarResult] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard Self.isEligible(query: q) else { return [] }
        let paths = await SpotlightRun(name: q).run()
        guard !Task.isCancelled else { return [] }
        return Self.makeResults(paths: paths, home: NSHomeDirectory())
    }
}

/// One NSMetadataQuery, finished exactly once: on gathering, on timeout or on cancellation.
@MainActor
private final class SpotlightRun {
    private let query = NSMetadataQuery()
    private var continuation: CheckedContinuation<[String], Never>?
    private var observer: NSObjectProtocol?
    private var finished = false

    init(name: String) {
        query.predicate = NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, name)
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
    }

    func run() async -> [String] {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<[String], Never>) in
                guard !Task.isCancelled else { c.resume(returning: []); return }
                continuation = c
                observer = NotificationCenter.default.addObserver(
                    forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.finish(collect: true) }
                }
                guard query.start() else { finish(collect: false); return }
                Task { [weak self] in
                    try? await Task.sleep(for: FileSource.timeout)
                    self?.finish(collect: true)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(collect: false) }
        }
    }

    private func finish(collect: Bool) {
        guard !finished else { return }
        finished = true
        query.disableUpdates()
        var paths: [String] = []
        if collect {
            // Over-read a little: exclusions are applied afterwards, the cap after them.
            let count = min(query.resultCount, FileSource.maxResults * 5)
            for i in 0..<count {
                if let item = query.result(at: i) as? NSMetadataItem,
                   let path = item.value(forAttribute: NSMetadataItemPathKey) as? String { paths.append(path) }
            }
        }
        query.stop()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        continuation?.resume(returning: paths)
        continuation = nil
    }
}
