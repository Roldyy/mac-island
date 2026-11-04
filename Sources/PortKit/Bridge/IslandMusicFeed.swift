// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Perf lane 1. New file: hands the system Now Playing reading (the event driven adapter) to the app, so the Now
// Playing feature can stop polling AppleScript while the adapter delivers.

import Combine
import Foundation

/// What plays, as plain public values (the app maps it to the Now Playing feature's own type: neither module imports the other).
public struct PortMusicReading: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var artworkData: Data?
    public var isPlaying: Bool
    /// Seconds at `sampledAt`.
    public var position: TimeInterval
    public var duration: TimeInterval
    public var rate: Double
    public var sampledAt: Date
    public var bundleID: String

    public init(title: String, artist: String, album: String, artworkData: Data?, isPlaying: Bool, position: TimeInterval,
                duration: TimeInterval, rate: Double, sampledAt: Date, bundleID: String) {
        self.title = title; self.artist = artist; self.album = album; self.artworkData = artworkData
        self.isPlaying = isPlaying; self.position = position; self.duration = duration
        self.rate = rate; self.sampledAt = sampledAt; self.bundleID = bundleID
    }
}

/// The state the app needs: the adapter is live (running and answered) with a reading or nothing playing, or it is not.
enum MusicFeedState: Equatable {
    case unavailable
    case live(PortMusicReading?)

    @MainActor init(playback: NotchPlayback?, isLive: Bool) {
        guard isLive else { self = .unavailable; return }
        self = .live(playback.map(PortMusicFeed.reading(from:)))
    }
}

@MainActor
public enum PortMusicFeed {
    private static var subscription: AnyCancellable?

    static func reading(from playback: NotchPlayback) -> PortMusicReading {
        PortMusicReading(
            title: (playback.track.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            artist: playback.track.artist ?? "", album: playback.track.album ?? "",
            artworkData: playback.track.artworkData, isPlaying: playback.isPlaying,
            position: playback.hasPosition ? playback.elapsed : 0, duration: playback.duration,
            rate: playback.rate, sampledAt: playback.sampledAt,
            bundleID: playback.track.appBundleIdentifier ?? "")
    }

    /// Calls `onReading` with every change of what the adapter reports while it is live, and `onUnavailable` once
    /// when it is not (never started, restarting, stopped, crashed). Event driven: the service publishes, nothing polls.
    /// Idempotent: a second call replaces the first.
    public static func observe(onReading: @escaping @MainActor (PortMusicReading?) -> Void,
                               onUnavailable: @escaping @MainActor () -> Void) {
        let service = NotchMusicService.shared
        subscription = service.objectWillChange
            .map { _ in () }
            .prepend(())                       // the adapter may already be live
            .receive(on: DispatchQueue.main)   // after the change, the service state is final
            .map { _ -> MusicFeedState in
                MainActor.assumeIsolated {
                    MusicFeedState(playback: service.playback,
                                   isLive: MusicSession.shared.isPlaybackRunning && service.adapterIsLive)
                }
            }
            .removeDuplicates()
            .sink { state in
                MainActor.assumeIsolated {
                    switch state {
                    case .unavailable: onUnavailable()
                    case .live(let reading): onReading(reading)
                    }
                }
            }
    }
}
