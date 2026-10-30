import Foundation

/// Installed applications: a bounded scan of the standard folders. Names and bundle URLs only;
/// nothing is read from inside a bundle.
struct AppSource: ResultSource {
    let sourceID = "apps"
    var directories: [URL] = AppSource.defaultDirectories
    private let catalog = Catalog()

    static var defaultDirectories: [URL] {
        [URL(fileURLWithPath: "/Applications", isDirectory: true),
         URL(fileURLWithPath: "/System/Applications", isDirectory: true),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)]
    }

    init(directories: [URL] = AppSource.defaultDirectories) { self.directories = directories }

    func results(for query: String) async -> [BarResult] {
        catalog.apps(scanning: directories)
    }

    /// One level of sub-folders is followed (Utilities); bundles are never entered.
    static func scan(directories: [URL], maxDepth: Int = 2) -> [BarResult] {
        var out: [BarResult] = []
        var seen = Set<String>()
        func walk(_ dir: URL, depth: Int) {
            let items = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            for url in items {
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                guard isDir else { continue }
                if url.pathExtension == "app" {
                    guard seen.insert(url.path).inserted else { continue }
                    out.append(BarResult(id: "app:\(url.path)", title: url.deletingPathExtension().lastPathComponent,
                                         subtitle: "Application", kind: .app, action: .open(url), reveal: url))
                } else if depth < maxDepth {
                    walk(url, depth: depth + 1)
                }
            }
        }
        for d in directories { walk(d, depth: 1) }
        return out
    }

    /// Scan cache, refreshed after a minute so a freshly installed app shows up.
    private final class Catalog: @unchecked Sendable {
        private let lock = NSLock()
        private var cached: [BarResult] = []
        private var at = Date.distantPast

        func apps(scanning dirs: [URL]) -> [BarResult] {
            lock.lock()
            if Date().timeIntervalSince(at) < 60, !cached.isEmpty { defer { lock.unlock() }; return cached }
            lock.unlock()
            let fresh = AppSource.scan(directories: dirs)
            lock.lock(); cached = fresh; at = Date(); lock.unlock()
            return fresh
        }
    }
}
