import AppKit
import Foundation
import Observation

enum ShelfSegment: String, CaseIterable, Identifiable {
    case shelf = "Étagère"
    case downloads = "Téléchargements"
    var id: String { rawValue }
}

/// State of the island tab that is still ours: which segment shows and the Downloads pane. The shelf's items are the
/// ported service's (`PortShelf.strip()`); the Downloads pane moves to the port in wave 8.
@MainActor @Observable
final class ShelfModel {
    var segment: ShelfSegment = .shelf
    private(set) var downloads: DownloadsSnapshot = .init(state: .ok, items: [], hasPending: false)

    let settings: ShelfSettings
    private var monitor: DownloadsMonitor?
    private let downloadsDirectory: URL
    private var started = false

    var downloadsEnabled: Bool { settings.downloadsEnabled }

    init(settings: ShelfSettings = ShelfSettings(),
         downloadsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)) {
        self.settings = settings
        self.downloadsDirectory = downloadsDirectory
    }

    /// Idempotent. Starts the Downloads watcher (first read may show the system permission prompt once).
    func start() {
        guard !started else { return }
        started = true
        guard settings.downloadsEnabled else { return }
        let limit = settings.downloadsLimit
        let monitor = DownloadsMonitor(directory: downloadsDirectory, limit: { limit }) { [weak self] snap in
            Task { @MainActor in self?.downloads = snap }
        }
        self.monitor = monitor
        monitor.start()
    }

    // MARK: Actions on a downloaded file

    func dragProvider(path: String) -> NSItemProvider {
        NSItemProvider(object: URL(fileURLWithPath: path) as NSURL)
    }

    func reveal(path: String) {
        var st = stat()
        guard !path.isEmpty, lstat(path, &st) == 0 else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func icon(forPath path: String) -> NSImage {
        let img = NSWorkspace.shared.icon(forFile: path)
        img.size = NSSize(width: 32, height: 32)
        return img
    }

    func refreshDownloads() { monitor?.refresh() }
}
