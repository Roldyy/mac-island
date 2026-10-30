import AppKit

/// What a pasteboard change carried, already size-capped.
enum PasteboardCapture: Equatable {
    case text(String)
    case image(png: Data, width: Int, height: Int)
    case files([String])
}

/// Polls `NSPasteboard.changeCount` every 0.5 s on the main run loop.
/// Items marked concealed/transient/auto-generated, or copied while an excluded app is in
/// front, are reported as a change (so auto-clear still runs) with no capture.
/// Content is never logged.
@MainActor
final class PasteboardWatcher {
    static let interval: TimeInterval = 0.5

    private let pasteboard: NSPasteboard
    private var timer: Timer?
    private(set) var lastChangeCount: Int

    var settings: () -> ClipboardSettings = { ClipboardSettings() }
    var frontmostBundleID: () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    /// Test seam: runs between reading the pasteboard and re-checking it.
    var afterCaptureRead: () -> Void = {}
    var onChange: (_ changeCount: Int, _ capture: PasteboardCapture?, _ source: String?) -> Void = { _, _, _ in }

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let t = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call right after the app itself wrote to the pasteboard, so it is not recorded back.
    func syncToCurrent() { lastChangeCount = pasteboard.changeCount }

    func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        let types = pasteboardTypes()
        guard !types.isEmpty else { return }   // cleared pasteboard
        let source = frontmostBundleID()
        let s = settings()
        let allowed = PasteboardFilter.shouldRecord(types: types, frontmostBundleID: source, excluded: s.excludedBundleIDs)
        var result = allowed && s.historyEnabled ? capture() : nil
        afterCaptureRead()
        // The pasteboard may have changed while we read it (or the item gained a concealed
        // marker): never record what is no longer what we looked at.
        if result != nil {
            let stillSame = pasteboard.changeCount == count
            let stillAllowed = PasteboardFilter.shouldRecord(types: pasteboardTypes(), frontmostBundleID: source,
                                                             excluded: s.excludedBundleIDs)
            if !stillSame || !stillAllowed { result = nil }
        }
        onChange(count, result, source)
    }

    private func pasteboardTypes() -> [String] {
        var all = pasteboard.types?.map(\.rawValue) ?? []
        for item in pasteboard.pasteboardItems ?? [] { all.append(contentsOf: item.types.map(\.rawValue)) }
        return all
    }

    private func capture() -> PasteboardCapture? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return .files(urls.map(\.path))
        }
        if let text = pasteboard.string(forType: .string) {
            return PasteboardFilter.textAllowed(byteCount: text.utf8.count) ? .text(text) : nil
        }
        return imageCapture()
    }

    private func imageCapture() -> PasteboardCapture? {
        if let png = pasteboard.data(forType: .png) {
            guard PasteboardFilter.imageAllowed(byteCount: png.count),
                  let rep = NSBitmapImageRep(data: png) else { return nil }
            return .image(png: png, width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        if let tiff = pasteboard.data(forType: .tiff) {
            guard PasteboardFilter.imageAllowed(byteCount: tiff.count),
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]),
                  PasteboardFilter.imageAllowed(byteCount: png.count) else { return nil }
            return .image(png: png, width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return nil
    }
}
