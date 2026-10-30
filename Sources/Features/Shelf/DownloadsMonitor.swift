import Foundation

/// The two file-system touches the monitor makes, injectable so tests can play "access denied, then granted".
struct DownloadsFileSystem: Sendable {
    var list: @Sendable (URL, Int, Date, inout DownloadTracker) -> DownloadsSnapshot
    /// A descriptor for change events, or a negative number when the folder cannot be opened.
    var openForEvents: @Sendable (String) -> Int32

    static let live = DownloadsFileSystem(
        list: { dir, limit, now, tracker in DownloadsLister.list(directory: dir, limit: limit, now: now, tracker: &tracker) },
        openForEvents: { open($0, O_EVTONLY) })
}

/// Watches a folder with a DispatchSource and publishes snapshots on the main queue.
/// All state lives on one serial queue. Never logs file names.
final class DownloadsMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "be.roldy.macisland.downloads")
    private let directory: URL
    private let limit: @Sendable () -> Int
    private let onSnapshot: @Sendable (DownloadsSnapshot) -> Void
    private let fileSystem: DownloadsFileSystem
    private var tracker: DownloadTracker
    private var source: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?
    private var started = false

    init(directory: URL, settle: TimeInterval = 2, fileSystem: DownloadsFileSystem = .live,
         limit: @escaping @Sendable () -> Int,
         onSnapshot: @escaping @Sendable (DownloadsSnapshot) -> Void) {
        self.directory = directory
        self.fileSystem = fileSystem
        self.tracker = DownloadTracker(settle: settle)
        self.limit = limit
        self.onSnapshot = onSnapshot
    }

    /// Idempotent.
    func start() {
        queue.async { [self] in
            guard !started else { return }
            started = true
            scan()
            attach()
        }
    }

    /// Rescans now. Also the way back from .denied / .missing: the folder watcher is attached by the
    /// first scan that can read the folder.
    func refresh() { queue.async { [self] in scan() } }

    func stop() {
        queue.async { [self] in
            source?.cancel(); source = nil
            debounce?.cancel(); debounce = nil
            started = false
        }
    }

    private func attach() {
        guard source == nil else { return }
        let fd = fileSystem.openForEvents(directory.path)
        guard fd >= 0 else { return }  // denied or missing: the snapshot already says so
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: queue)
        src.setEventHandler { [weak self] in self?.scheduleScan(after: 0.4) }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func scheduleScan(after delay: TimeInterval) {
        debounce?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.scan() }
        debounce = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func scan() {
        let snap = fileSystem.list(directory, limit(), Date(), &tracker)
        if snap.state == .ok { attach() }
        let publish = onSnapshot
        DispatchQueue.main.async { publish(snap) }
        if snap.hasPending { scheduleScan(after: tracker.settle + 0.5) }
    }
}
