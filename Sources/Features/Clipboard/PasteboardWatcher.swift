import AppKit
import IslandKit

/// What a pasteboard change carried, already size-capped.
enum PasteboardCapture: Equatable {
    case text(String)
    case image(png: Data, width: Int, height: Int)
    case files([String])
}

/// Follows `NSPasteboard.changeCount` through the shared `PasteboardChangeHub` (one timer and one read of the count
/// for every clipboard service, at 0.5 s); the hub runs only while this watcher (or another service) is subscribed.
/// Items marked concealed/transient/auto-generated, or copied while an excluded app is in
/// front, are reported as a change (so auto-clear still runs) with no capture.
/// Content is never logged.
///
/// Every read of the pasteboard (types, items, text, images, the "still the same?" re-check) runs on the app-wide
/// `GeneralPasteboardLane`, never on the main thread: AppKit's type cache on the general pasteboard is not thread-safe
/// (1.1.0 crashes) and a read can block behind an app that promised content. The result comes back to main.
@MainActor
final class PasteboardWatcher {
    static let interval: TimeInterval = 0.5

    private let pasteboard: NSPasteboard
    private let hub: PasteboardChangeHub
    private let lane: GeneralPasteboardLane
    private var subscription: PasteboardChangeHub.Token?
    /// Bumped by `stop()`: a lane read still in flight then delivers nothing.
    private var runGeneration = 0
    private(set) var lastChangeCount: Int
    /// True once a count read on the lane has been adopted (start() asks for one): tests wait on it before writing.
    private(set) var hasAdoptedCount = false
    /// Lane round trips in flight (a count read, a look at the contents). Zero = nothing pending: tests wait on it.
    private var busy = 0
    var isIdle: Bool { busy == 0 }
    /// A count lower than `lastChangeCount` is a read that started before our own write (stale), not a copy. The
    /// same lower count three times in a row means the pasteboard server restarted: adopt it.
    private var staleCount: (value: Int, times: Int)?

    var settings: () -> ClipboardSettings = { ClipboardSettings() }
    var frontmostBundleID: () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    /// Test seam: runs (on the lane) between reading the pasteboard and re-checking it.
    var afterCaptureRead: () -> Void = {}
    var onChange: (_ changeCount: Int, _ capture: PasteboardCapture?, _ source: String?) -> Void = { _, _, _ in }

    /// The general pasteboard shares the app-wide hub; any other pasteboard (tests) gets a hub of its own that
    /// reads that pasteboard.
    init(pasteboard: NSPasteboard = .general, hub: PasteboardChangeHub? = nil,
         lane: GeneralPasteboardLane = .shared) {
        self.pasteboard = pasteboard
        self.lane = lane
        self.lastChangeCount = 0   // set from the lane by start(); no read of the pasteboard on main
        self.hub = hub ?? (pasteboard === NSPasteboard.general
            ? .shared
            : PasteboardChangeHub(reader: { done in done(pasteboard.changeCount) }))
    }

    var isRunning: Bool { subscription != nil }

    func start() {
        guard subscription == nil else { return }
        // Adopt the pasteboard as it is now, so what was copied before start is never recorded. Read on the lane;
        // until it answers, a hub count equal to the current one would look like a copy, so the first poll waits for it.
        syncToCurrent()
        subscription = hub.subscribe(interval: Self.interval) { [weak self] count in self?.poll(changeCount: count) }
    }

    func stop() {
        runGeneration &+= 1
        if let subscription { hub.unsubscribe(subscription) }
        subscription = nil
    }

    /// Call right after the app itself wrote to the pasteboard, so it is not recorded back.
    /// The count is read on the lane (queued behind that write) and adopted on main; a hub read that was queued
    /// before the write lands lower and is treated as stale, one queued after it lands equal.
    func syncToCurrent() {
        let pasteboard = pasteboard
        let generation = runGeneration
        lane.async({ pasteboard.changeCount }, then: { [weak self] count in
            MainActor.assumeIsolated {
                guard let self, self.runGeneration == generation else { return }
                self.lastChangeCount = count
                self.hasAdoptedCount = true
            }
        })
    }

    /// Same, when the caller already read the count of its own write on the lane.
    func syncToCurrent(count: Int) { lastChangeCount = count; hasAdoptedCount = true }

    /// How many times the loop looked at the pasteboard (changed or not): lets a test wait for N ticks instead of
    /// sleeping for a guessed time before asserting that nothing was recorded.
    private(set) var pollCount = 0

    /// Looks at the pasteboard now: asks the lane for the count, then behaves like a hub tick. Tests and
    /// "check right away" callers.
    func poll() {
        let pasteboard = pasteboard
        busy += 1
        lane.async({ pasteboard.changeCount }, then: { [weak self] count in
            MainActor.assumeIsolated {
                self?.poll(changeCount: count)
                self?.busy -= 1   // after the look was queued, so `isIdle` is never true in between
            }
        })
    }

    /// One look with a count the hub already read. The count comparison happens here on main (no pasteboard access);
    /// everything that touches the pasteboard runs on the lane and `onChange` is delivered on main afterwards.
    func poll(changeCount count: Int) {
        pollCount += 1
        guard count != lastChangeCount else { staleCount = nil; return }
        if count < lastChangeCount {
            let times = staleCount?.value == count ? (staleCount?.times ?? 0) + 1 : 1
            staleCount = (count, times)
            guard times >= 3 else { return }
        }
        staleCount = nil
        lastChangeCount = count

        // Main-thread inputs are read now, the pasteboard is read later on the lane.
        let source = frontmostBundleID()
        let s = settings()
        let afterRead = afterCaptureRead
        let reader = PasteboardLaneReader(pasteboard: pasteboard)
        let generation = runGeneration
        busy += 1
        lane.async({ reader.look(count: count, source: source, settings: s, afterCaptureRead: afterRead) },
                   then: { [weak self] outcome in
            MainActor.assumeIsolated {
                guard let self else { return }
                defer { self.busy -= 1 }
                // A look that finished after `stop()` reports nothing; nil = cleared pasteboard.
                guard self.runGeneration == generation, let outcome else { return }
                self.onChange(count, outcome, source)
            }
        })
    }
}

/// The lane-side half of a poll. Not isolated to the main actor: it only ever runs on `GeneralPasteboardLane`.
private struct PasteboardLaneReader: @unchecked Sendable {
    let pasteboard: NSPasteboard

    /// `nil` = nothing to report (cleared pasteboard); `.some(nil)` = a change with no capture.
    func look(count: Int, source: String?, settings s: ClipboardSettings,
              afterCaptureRead: () -> Void) -> PasteboardCapture?? {
        let types = pasteboardTypes()
        guard !types.isEmpty else { return nil }
        let allowed = PasteboardFilter.shouldRecord(types: types, frontmostBundleID: source, excluded: s.excludedBundleIDs)
        var result = allowed && s.historyEnabled
            ? capture(includeImagesAndFiles: s.includeImagesAndFiles, skipSensitiveText: s.filterSensitiveText) : nil
        afterCaptureRead()
        // The pasteboard may have changed while we read it (or the item gained a concealed
        // marker): never record what is no longer what we looked at.
        if result != nil {
            let stillSame = pasteboard.changeCount == count
            let stillAllowed = PasteboardFilter.shouldRecord(types: pasteboardTypes(), frontmostBundleID: source,
                                                             excluded: s.excludedBundleIDs)
            if !stillSame || !stillAllowed { result = nil }
        }
        return .some(result)
    }

    private func pasteboardTypes() -> [String] {
        var all = pasteboard.types?.map(\.rawValue) ?? []
        for item in pasteboard.pasteboardItems ?? [] { all.append(contentsOf: item.types.map(\.rawValue)) }
        return all
    }

    private func capture(includeImagesAndFiles: Bool, skipSensitiveText: Bool) -> PasteboardCapture? {
        if includeImagesAndFiles,
           let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return .files(urls.map(\.path))
        }
        if let text = pasteboard.string(forType: .string) {
            guard PasteboardFilter.textAllowed(byteCount: text.utf8.count) else { return nil }
            // The opt-in guess: reported as a change with no capture, like a concealed copy (auto-clear still runs).
            if skipSensitiveText, SensitiveTextFilter.looksSensitive(text) { return nil }
            return .text(text)
        }
        return includeImagesAndFiles ? imageCapture() : nil
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
