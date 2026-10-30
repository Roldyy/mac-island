import Foundation

struct DownloadItem: Equatable, Identifiable {
    var id: String { path }
    let path: String
    let name: String
    let modified: Date
    let isDirectory: Bool
    let isSymlink: Bool
}

struct DownloadsSnapshot: Equatable {
    enum State: Equatable { case ok, denied, missing }
    var state: State
    var items: [DownloadItem]
    /// Some files are still being written: the caller rescans after the settle delay.
    var hasPending: Bool
}

enum DownloadsLister {
    /// Reads the folder once. Listing a protected folder is what triggers the system prompt.
    static func list(directory: URL, limit: Int, now: Date,
                     tracker: inout DownloadTracker) -> DownloadsSnapshot {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)
        } catch {
            return DownloadsSnapshot(state: classify(error), items: [], hasPending: false)
        }
        var finished: [DownloadItem] = []
        var pending = false
        var names = Set<String>()
        for url in urls where !DownloadFilter.isPartialOrHidden(url.lastPathComponent) {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let modified = values?.contentModificationDate ?? .distantPast
            let size = Int64(values?.fileSize ?? 0)
            names.insert(url.path)
            if tracker.isFinished(path: url.path, size: size, modified: modified, now: now) {
                finished.append(DownloadItem(path: url.path, name: url.lastPathComponent, modified: modified,
                                             isDirectory: values?.isDirectory ?? false,
                                             isSymlink: values?.isSymbolicLink ?? false))
            } else {
                pending = true
            }
        }
        tracker.retain(only: names)
        finished.sort { $0.modified > $1.modified }
        return DownloadsSnapshot(state: .ok, items: Array(finished.prefix(max(0, limit))), hasPending: pending)
    }

    static func classify(_ error: Error) -> DownloadsSnapshot.State {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            if ns.code == NSFileReadNoPermissionError { return .denied }
            if ns.code == NSFileReadNoSuchFileError || ns.code == NSFileNoSuchFileError { return .missing }
        }
        if ns.domain == NSPOSIXErrorDomain {
            if ns.code == Int(EPERM) || ns.code == Int(EACCES) { return .denied }
            if ns.code == Int(ENOENT) { return .missing }
        }
        if let under = ns.userInfo[NSUnderlyingErrorKey] as? NSError, under !== ns { return classify(under) }
        return .missing
    }
}
