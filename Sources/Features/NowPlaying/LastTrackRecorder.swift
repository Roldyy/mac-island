import Foundation

/// Keeps the last played track on disk for the idle home card. Writes only when something changed:
/// a new track, its cover arriving, or the moment playback stops (so the time shown is when it stopped).
/// Switched off, it deletes the file and writes nothing.
@MainActor
final class LastTrackRecorder {
    private let file: any LastTrackFile
    private let isEnabled: () -> Bool
    private let now: () -> Date
    private let thumbnail: (Data) -> Data?

    private var currentKey: String?
    private var current: StoredTrack?
    private var coverStored = false
    private var wasPlaying = false
    private var clearedWhileOff = false
    private(set) var writes = 0

    init(file: any LastTrackFile = DiskLastTrackFile(), isEnabled: @escaping () -> Bool,
         now: @escaping () -> Date = { Date() }, thumbnail: @escaping (Data) -> Data? = LastTrackThumbnail.jpeg(from:)) {
        self.file = file
        self.isEnabled = isEnabled
        self.now = now
        self.thumbnail = thumbnail
    }

    /// After every poll. `artwork` is the model's current cover (any image format), nil while it is loading.
    func observe(_ snapshot: NowPlayingSnapshot?, artwork: Data?) {
        guard isEnabled() else {
            forgetIfNeeded()
            return
        }
        clearedWhileOff = false
        if let snapshot, snapshot.isPlaying, !snapshot.title.isEmpty {
            let key = snapshot.trackKey
            if key != currentKey {
                currentKey = key
                coverStored = artwork != nil
                store(from: snapshot, cover: artwork.flatMap(thumbnail))
            } else if !coverStored, let artwork {
                // The cover arrived after the title: one more write, then the track is complete.
                coverStored = true
                store(from: snapshot, cover: thumbnail(artwork))
            }
            wasPlaying = true
        } else if wasPlaying, var stopped = current {
            wasPlaying = false
            stopped.timestamp = now()
            current = stopped
            write(stopped)
        }
    }

    /// The Settings flag changed: switched off, the file is removed at once rather than at the next poll.
    func settingsChanged() {
        if !isEnabled() { forgetIfNeeded() }
    }

    private func store(from snapshot: NowPlayingSnapshot, cover: Data?) {
        let track = StoredTrack(title: snapshot.title, artist: snapshot.artist, album: snapshot.album,
                                playerBundleID: snapshot.sourceBundleID, timestamp: now(), artwork: cover)
        current = track
        write(track)
    }

    private func write(_ track: StoredTrack) {
        writes += 1
        file.write(track)
    }

    private func forgetIfNeeded() {
        if !clearedWhileOff {
            clearedWhileOff = true
            file.clear()
        }
        currentKey = nil
        current = nil
        coverStored = false
        wasPlaying = false
    }
}
