import AppKit
import Foundation
import Testing
@testable import NowPlayingFeature

private final class MemoryFile: LastTrackFile, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: StoredTrack?
    private var clears = 0
    var writes: [StoredTrack] = []

    func write(_ track: StoredTrack) { lock.lock(); stored = track; writes.append(track); lock.unlock() }
    func read() -> StoredTrack? { lock.lock(); defer { lock.unlock() }; return stored }
    func clear() { lock.lock(); stored = nil; clears += 1; lock.unlock() }
    var clearCount: Int { lock.lock(); defer { lock.unlock() }; return clears }
}

private func track(_ title: String, bundle: String = "com.spotify.client", artist: String = "A",
                   playing: Bool = true) -> NowPlayingSnapshot {
    NowPlayingSnapshot(title: title, artist: artist, album: "Al", artworkURL: nil, artworkData: nil,
                       isPlaying: playing, position: 1, duration: 100, sourceBundleID: bundle)
}

@MainActor
@Suite struct LastTrackRecorderTests {
    private final class Clock: @unchecked Sendable { var date = Date(timeIntervalSince1970: 1_700_000_000) }

    private func make(enabled: @escaping () -> Bool = { true }, clock: Clock = Clock())
        -> (recorder: LastTrackRecorder, file: MemoryFile, clock: Clock) {
        let file = MemoryFile()
        let recorder = LastTrackRecorder(file: file, isEnabled: enabled, now: { clock.date },
                                         thumbnail: { _ in Data([1, 2, 3]) })
        return (recorder, file, clock)
    }

    @Test func aPlayingTrackIsKeptWithItsPlayer() {
        let bench = make()
        bench.recorder.observe(track("Reason", bundle: "com.apple.Music", artist: "Bonobo"), artwork: nil)
        let stored = bench.file.read()
        #expect(stored?.title == "Reason" && stored?.artist == "Bonobo" && stored?.album == "Al")
        #expect(stored?.playerBundleID == "com.apple.Music")
        #expect(stored?.timestamp == bench.clock.date)
        #expect(stored?.artwork == nil)
    }

    @Test func writesOnlyWhenTheTrackChanges() {
        let bench = make()
        for _ in 0..<20 { bench.recorder.observe(track("Same"), artwork: nil) }
        #expect(bench.recorder.writes == 1)
        bench.recorder.observe(track("Other"), artwork: nil)
        #expect(bench.recorder.writes == 2)
        #expect(bench.file.read()?.title == "Other")
    }

    @Test func theCoverArrivingLaterIsOneMoreWriteThenNoMore() {
        let bench = make()
        bench.recorder.observe(track("Song"), artwork: nil)
        bench.recorder.observe(track("Song"), artwork: nil)
        #expect(bench.recorder.writes == 1)
        bench.recorder.observe(track("Song"), artwork: Data([9]))
        #expect(bench.recorder.writes == 2)
        #expect(bench.file.read()?.artwork == Data([1, 2, 3]))
        for _ in 0..<10 { bench.recorder.observe(track("Song"), artwork: Data([9])) }
        #expect(bench.recorder.writes == 2)
    }

    @Test func stoppingStampsTheTimeOnceAndKeepsTheTrack() {
        let bench = make()
        bench.recorder.observe(track("Song"), artwork: Data([9]))
        let started = bench.clock.date
        bench.clock.date = started.addingTimeInterval(600)
        bench.recorder.observe(track("Song", playing: false), artwork: Data([9]))
        #expect(bench.file.read()?.timestamp == started.addingTimeInterval(600))
        #expect(bench.file.read()?.title == "Song")
        #expect(bench.file.read()?.artwork == Data([1, 2, 3]))
        let writes = bench.recorder.writes
        bench.clock.date = started.addingTimeInterval(1_200)
        bench.recorder.observe(nil, artwork: nil)
        bench.recorder.observe(track("Song", playing: false), artwork: nil)
        #expect(bench.recorder.writes == writes)
        #expect(bench.file.read()?.timestamp == started.addingTimeInterval(600))
    }

    @Test func aPlayerQuittingStampsTheTimeToo() {
        let bench = make()
        bench.recorder.observe(track("Song"), artwork: nil)
        bench.clock.date = bench.clock.date.addingTimeInterval(90)
        bench.recorder.observe(nil, artwork: nil)
        #expect(bench.file.read()?.timestamp == bench.clock.date)
    }

    @Test func nothingPlayingAtLaunchNeverEraseWhatIsKept() {
        let bench = make()
        bench.file.write(StoredTrack(title: "Yesterday", artist: "", album: "", playerBundleID: "x", timestamp: Date(), artwork: nil))
        let before = bench.file.writes.count
        bench.recorder.observe(nil, artwork: nil)
        bench.recorder.observe(track("Paused", playing: false), artwork: nil)
        #expect(bench.file.read()?.title == "Yesterday")
        #expect(bench.file.writes.count == before)
    }

    @Test func switchedOffNothingIsWrittenAndTheFileIsRemoved() {
        var enabled = true
        let bench = make(enabled: { enabled })
        bench.recorder.observe(track("Song"), artwork: nil)
        #expect(bench.file.read() != nil)
        enabled = false
        bench.recorder.settingsChanged()
        #expect(bench.file.read() == nil)
        for _ in 0..<5 { bench.recorder.observe(track("Song"), artwork: nil) }
        #expect(bench.file.read() == nil)
        #expect(bench.file.clearCount == 1)  // not one delete per poll
        enabled = true
        bench.recorder.observe(track("Song"), artwork: nil)
        #expect(bench.file.read()?.title == "Song")
    }

    @Test func theFlagDefaultsToOn() {
        let name = "mis-nowplaying-flag-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(LastTrackSettings.isEnabled(defaults))
        defaults.set(false, forKey: "notchRememberLastTrack")
        #expect(!LastTrackSettings.isEnabled(defaults))
        #expect(LastTrackSettings.flagKey == "notchRememberLastTrack")
    }
}

@Suite struct StoredTrackFileTests {
    private func tempFile() -> (file: DiskLastTrackFile, url: URL, cleanup: () -> Void) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mis-np-last-\(UUID().uuidString)")
        let url = folder.appendingPathComponent("Data/last-track")
        return (DiskLastTrackFile(url: url), url, { try? FileManager.default.removeItem(at: folder) })
    }

    @Test func roundTripAtomicAndPrivate() throws {
        let bench = tempFile()
        defer { bench.cleanup() }
        let track = StoredTrack(title: "T", artist: "A", album: "Al", playerBundleID: "com.apple.Music",
                                timestamp: Date(timeIntervalSince1970: 1_700_000_000), artwork: Data([1, 2]))
        bench.file.write(track)
        #expect(bench.file.read() == track)
        let mode = try #require(try FileManager.default.attributesOfItem(atPath: bench.url.path)[.posixPermissions] as? NSNumber)
        #expect(mode.intValue == 0o600)
        bench.file.clear()
        #expect(bench.file.read() == nil)
    }

    @Test func corruptionIsDiscarded() throws {
        let bench = tempFile()
        defer { bench.cleanup() }
        try FileManager.default.createDirectory(at: bench.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        for garbage in ["", "nope", "{}", #"{"version":9,"title":"x","artist":"","album":"","playerBundleID":"a","timestamp":1}"#] {
            try Data(garbage.utf8).write(to: bench.url)
            #expect(bench.file.read() == nil, "\(garbage)")
        }
    }

    @Test func sizeIsCapped() {
        let huge = StoredTrack(title: "T", artist: "", album: "", playerBundleID: "x", timestamp: Date(),
                               artwork: Data(repeating: 1, count: StoredTrack.maxFileBytes))
        #expect(huge.encoded() == nil)
        #expect(StoredTrack(title: String(repeating: "x", count: 9_999), artist: "", album: "", playerBundleID: "x",
                            timestamp: Date(), artwork: nil).title.count == StoredTrack.maxTextLength)
        #expect(StoredTrack.decode(Data(repeating: 0x20, count: StoredTrack.maxFileBytes + 1)) == nil)
    }

    /// The text ShellKit's `LastTrackRecord` is tested against: the reader and this writer must agree.
    @Test func theFileContractMatchesTheReader() throws {
        let json = #"{"version":1,"title":"Reason","artist":"Bonobo","album":"Migration","playerBundleID":"com.spotify.client","timestamp":1700000000,"artwork":"/9j/2Q=="}"#
        let decoded = try #require(StoredTrack.decode(Data(json.utf8)))
        #expect(decoded == StoredTrack(title: "Reason", artist: "Bonobo", album: "Migration",
                                       playerBundleID: "com.spotify.client",
                                       timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                                       artwork: Data([0xFF, 0xD8, 0xFF, 0xD9])))
        let encoded = try #require(decoded.encoded())
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(object.keys) == ["version", "title", "artist", "album", "playerBundleID", "timestamp", "artwork"])
    }
}

@Suite struct LastTrackThumbnailTests {
    private func png(side: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    @Test func aBigCoverBecomesASmallJPEG() throws {
        let jpeg = try #require(LastTrackThumbnail.jpeg(from: png(side: 900)))
        #expect(jpeg.prefix(2) == Data([0xFF, 0xD8]))
        #expect(jpeg.count <= LastTrackThumbnail.maxBytes)
        let image = try #require(NSBitmapImageRep(data: jpeg))
        #expect(max(image.pixelsWide, image.pixelsHigh) <= LastTrackThumbnail.maxPixels)
    }

    @Test func notAnImageGivesNil() {
        #expect(LastTrackThumbnail.jpeg(from: Data("hello".utf8)) == nil)
    }
}
