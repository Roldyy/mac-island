// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W8A (music: lyrics, queue, live equalizer, MediaRemote adapter). The lane owns this file.

import AppKit
import Combine
import IslandKit
import IslandUI
import SwiftUI

// MARK: - Closed island

/// What the closed island needs to know about the playing track. Pure value, so the mapping is tested without a player.
struct MusicNowPlaying: Equatable {
    var title: String
    var isPlaying: Bool
    /// 0...1 when the player reports a duration.
    var progress: Double?

    @MainActor init?(playback: NotchPlayback?, now: Date = Date()) {
        guard let playback else { return nil }
        let title = (playback.track.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title
        self.isPlaying = playback.isPlaying
        self.progress = playback.duration > 0 && playback.hasPosition
            ? min(1, max(0, playback.position(at: now) / playback.duration)) : nil
    }

    init(title: String, isPlaying: Bool, progress: Double?) {
        self.title = title
        self.isPlaying = isPlaying
        self.progress = progress
    }
}

/// The music activity of the ported stack, in the shape `AmbientBridge` turns into the music indicator (a note with
/// the progress ring on the left, the title with the equalizer bars on the right). Whether it is SHOWN stays the
/// user's choice: the `music` channel is a Settings switch, off by default (closed island rule), and `AmbientCenter`
/// applies it. A track with no title draws nothing (no icon-only item).
///
/// The id differs from the one our own Now Playing module posts (`music`), so the two never withdraw each other; when
/// both play, the arbiter keeps one item per wing (id order), so there is never a duplicate.
enum MusicActivity {
    static let id = "music.port"
    static let maximumTitle = 18
    /// The two glyphs `AmbientBridge` recognises as the music wing (its constants are internal to IslandKit).
    static let noteSymbol = "music.note"
    static let waveSymbol = "waveform"

    static func activity(for nowPlaying: MusicNowPlaying?) -> IslandActivity? {
        guard let nowPlaying, nowPlaying.isPlaying, !nowPlaying.title.isEmpty else { return nil }
        let title = nowPlaying.title.count > maximumTitle
            ? String(nowPlaying.title.prefix(maximumTitle - 1)) + "…" : nowPlaying.title
        return IslandActivity(
            id: id, source: AppFeature.notchLyrics.registryID, priority: .music,
            leading: CompactItem(symbol: noteSymbol, progress: nowPlaying.progress),
            trailing: CompactItem(symbol: waveSymbol, text: title))
    }
}

// MARK: - One music session for the three features and the tab

/// Everything the music stack does to the outside. The registry tests swap it for a recorder.
struct MusicRuntime {
    var capability: () -> MediaRemoteCapability
    /// Starts the adapter process and its readers.
    var startPlayback: @MainActor () -> Void
    var stopPlayback: @MainActor () -> Void
    var syncQueue: @MainActor () -> Void
    var syncLyrics: @MainActor () -> Void
    var stopLyrics: @MainActor () -> Void
    var syncEqualizer: @MainActor () -> Void
    var stopEqualizer: @MainActor () -> Void
    /// Starts watching playback for the closed island (live: a Combine sink; fake: records).
    var watchPlayback: @MainActor (_ onChange: @escaping @MainActor (MusicNowPlaying?) -> Void) -> AnyCancellable?
    var post: @MainActor (IslandActivity) -> Void
    var withdraw: @MainActor (String) -> Void

    static let live = MusicRuntime(
        capability: { MediaRemoteAdapterLocator.live.capability() },
        startPlayback: { NotchMusicService.shared.start() },
        stopPlayback: { NotchMusicService.shared.stop() },
        syncQueue: { NotchMusicService.shared.syncQueuePreference() },
        syncLyrics: { if !NotchLyricsSupport.isEnabled() { NotchLyricsService.shared.stop() } },
        stopLyrics: { NotchLyricsService.shared.stop() },
        syncEqualizer: { NotchAudioLevelService.shared.syncWithPreferences() },
        stopEqualizer: { NotchAudioLevelService.shared.stop() },
        watchPlayback: { onChange in
            NotchMusicService.shared.$playback
                .receive(on: DispatchQueue.main)
                .sink { playback in MainActor.assumeIsolated { onChange(MusicNowPlaying(playback: playback)) } }
        },
        post: { ActivityCenter.shared.post($0) },
        withdraw: { ActivityCenter.shared.withdraw(id: $0) })
}

/// Who needs the music stack right now: each of the three features, and the music tab while it is on screen. The
/// adapter process runs once for all of them, starts with the first, stops with the last, and never starts when
/// the capability probe says it cannot work (the tab then says why).
@MainActor
final class MusicSession {
    static let shared = MusicSession(runtime: .live)

    let runtime: MusicRuntime
    private var owners: Set<String> = []
    private var watcher: AnyCancellable?
    private(set) var isPlaybackRunning = false

    init(runtime: MusicRuntime) { self.runtime = runtime }

    var capability: MediaRemoteCapability { runtime.capability() }

    func acquire(_ owner: String) {
        owners.insert(owner)
        PortIslandHosting.acquire("music")
        guard !isPlaybackRunning, capability.isAvailable else { return }
        isPlaybackRunning = true
        runtime.startPlayback()
        watcher = runtime.watchPlayback { [weak self] nowPlaying in self?.publish(nowPlaying) }
    }

    func release(_ owner: String) {
        owners.remove(owner)
        guard owners.isEmpty else { return }
        PortIslandHosting.release("music")
        watcher = nil
        runtime.withdraw(MusicActivity.id)
        if isPlaybackRunning {
            isPlaybackRunning = false
            runtime.stopPlayback()
        }
    }

    private func publish(_ nowPlaying: MusicNowPlaying?) {
        if let activity = MusicActivity.activity(for: nowPlaying) { runtime.post(activity) }
        else { runtime.withdraw(MusicActivity.id) }
    }

    func isHeld(by owner: String) -> Bool { owners.contains(owner) }
}

// MARK: - Lane

/// The music lane: three ported features bound as new registry features, `notchLyrics` (synchronised lyrics, LRCLIB),
/// `notchQueue` (up next) and `notchLiveEqualizer` (bars that follow the real sound), all off until the user turns
/// them on. They share one `MusicSession`.
///
/// Decisions, in the order they matter:
/// - The read of the system Now Playing session (artist, title, cover, progress, transport, queue) is the ported
///   adapter (`Sources/NowPlayingAdapter`) run inside `/usr/bin/perl`. `MediaRemoteAdapterLocator` probes it and has a
///   kill switch; without it the music page says why it cannot read, it never crashes. Our own Now Playing module
///   (AppleScript, Automation) stays untouched and keeps the Home card; retiring it is a wiring change outside this lane.
/// - Nothing prompts. Lyrics and the queue only talk to `lrclib.net`/`musicbrainz.org` and the player. The equalizer
///   creates an audio process tap only after the "Autoriser" click that the mixer lane's probe records
///   (`MixerAudioCapture`, patch 1601): the same System Audio Recording permission, never a second prompt.
/// - Our island closed state: the music wing exists only if the user switched the `music` indicator on.
enum MusicLane {
    static let owners: [AppFeature: String] = [
        .notchLyrics: "lyrics", .notchQueue: "queue", .notchLiveEqualizer: "equalizer",
    ]

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, session: .shared)
    }

    @MainActor static func bind(into binding: PortFeatureBinding, session: MusicSession) {
        let runtime = session.runtime
        binding.bind(.notchLyrics, start: {
            session.acquire("lyrics")
            runtime.syncLyrics()
        }, stop: {
            runtime.stopLyrics()
            session.release("lyrics")
        })
        binding.bind(.notchQueue, start: {
            session.acquire("queue")
            runtime.syncQueue()
        }, stop: {
            runtime.syncQueue()  // `NotchQueueSupport.isEnabled` is false by now: hides the queue and drops its covers
            session.release("queue")
        })
        binding.bind(.notchLiveEqualizer, start: {
            session.acquire("equalizer")
            runtime.syncEqualizer()
        }, stop: {
            runtime.stopEqualizer()
            session.release("equalizer")
        })
    }
}

// MARK: - Island tab

/// The island's "Musique" tab: the ported player (cover, transport, seek, source picker) with lyrics and the queue
/// below it when their features are on. Wiring it into the island's groups is `ShellTabs` / `ShellLayout` (outside
/// this lane): `PortIslandMusic.tab()` is the value to add.
public enum PortIslandMusic {
    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "music", title: "Musique", systemImage: "music.note") {
            AnyView(MusicIslandTab())
        }
    }
}

private struct MusicIslandTab: View {
    @State private var capability = MusicSession.shared.capability
    @ObservedObject private var permissions = Permissions.shared

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let reason = capability.unavailableReason {
                    MusicUnavailable(reason: reason)
                } else {
                    VStack(spacing: 8) {
                        NotchMusicView(size: proxy.size, extrasHeight: 150)
                        MusicEqualizerNotice()
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .environment(\.notchPresentation, true)
        .environment(\.colorScheme, .dark)
        .defaultAppStorage(PortHost.defaults)
        .onAppear {
            capability = MusicSession.shared.capability
            MusicSession.shared.acquire("tab")
        }
        .onDisappear { MusicSession.shared.release("tab") }
    }
}

/// Why nothing plays here, in words: a tab that looks empty hides a missing piece.
private struct MusicUnavailable: View {
    let reason: MediaRemoteUnavailableReason

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.slash").font(.title2).foregroundStyle(.secondary)
            Text("Lecture indisponible").font(.headline)
            Text(reason.message)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if reason == .killSwitch {
                Button("Réactiver la lecture du système") {
                    PortHost.defaults.set(false, forKey: MediaRemoteAdapterLocator.killSwitchKey)
                }
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The equalizer's one permission, asked by a click only: shown while the feature is on and the grant is missing.
private struct MusicEqualizerNotice: View {
    @State private var granted = MixerAudioCapture.allowsTaps
    @State private var equalizerOn = AppFeature.notchLiveEqualizer.isAvailable

    var body: some View {
        if equalizerOn && !granted {
            HStack(alignment: .firstTextBaseline) {
                Label("Égaliseur en direct : l’enregistrement audio du système n’est pas encore autorisé.",
                      systemImage: "waveform.badge.exclamationmark")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Autoriser") {
                    MixerAudioCapture.requestByClick(isAvailable: { AppFeature.notchLiveEqualizer.isAvailable })
                    granted = MixerAudioCapture.allowsTaps
                    NotchAudioLevelService.shared.syncWithPreferences()
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 10)
        }
    }
}
