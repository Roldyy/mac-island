import AppKit
import IslandUI
import SwiftUI

/// Artwork, title, artist and the three transport buttons. While nothing plays it is a call to action:
/// the last track (dimmed) when one is kept, "Ouvrir Spotify" otherwise; a click opens the player.
struct HomeNowPlayingCard: View {
    let track: HomeTrack?
    /// The kept last track and the player launcher; nil keeps the plain empty state.
    var idle: LastTrackModel?
    let send: (HomeTransport) -> Void

    private var isIdle: Bool { track == nil && idle != nil }
    private var last: LastTrackRecord? { track == nil ? idle?.record : nil }

    var body: some View {
        HStack(spacing: IslandSpacing.m) {
            if isIdle, let idle {
                Button { idle.open() } label: { info }
                    .buttonStyle(HomeTapStyle())
                    .help(idle.help)
                    .accessibilityLabel(idleAccessibilityLabel(idle))
            } else {
                info
            }
            HStack(spacing: IslandSpacing.xs) {
                transportButton(.previous, "backward.fill", "Morceau précédent")
                playButton
                transportButton(.next, "forward.fill", "Morceau suivant")
            }
        }
        .padding(.horizontal, IslandSpacing.m)
        .frame(height: HomeGeometry.nowPlayingCard)
        .background(IslandPalette.textPrimary.color.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: IslandRadius.large, style: .continuous))
        .overlay(alignment: .bottom) { progressBar }
        .clipShape(RoundedRectangle(cornerRadius: IslandRadius.large, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    /// Artwork and texts: the part of the card a click opens the player from when idle.
    private var info: some View {
        HStack(spacing: IslandSpacing.m) {
            artwork
            VStack(alignment: .leading, spacing: IslandSpacing.xxs) { texts }
            Spacer(minLength: IslandSpacing.s)
        }
        .opacity(last == nil ? 1 : 0.6)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var texts: some View {
        if let last {
            TimelineView(.everyMinute) { context in
                Text("Dernière lecture · \(LastTrackRelativeTime.text(since: last.timestamp, now: context.date))")
                    .font(.islandFootnote)
                    .foregroundStyle(IslandPalette.textSecondary.color)
                    .lineLimit(1)
            }
            Text(last.title)
                .font(.islandBodyEmphasis)
                .foregroundStyle(IslandPalette.textPrimary.color)
                .lineLimit(1)
            if !last.artist.isEmpty {
                Text(last.artist)
                    .font(.islandFootnote)
                    .foregroundStyle(IslandPalette.textSecondary.color)
                    .lineLimit(1)
            }
        } else {
            Text(track?.title ?? "Aucune lecture")
                .font(.islandBodyEmphasis)
                .foregroundStyle(IslandPalette.textPrimary.color)
                .lineLimit(1)
            if track == nil, let idle {
                HStack(spacing: IslandSpacing.xs) {
                    Text(idle.callToAction)
                    Image(systemName: "arrow.up.forward.app")
                }
                .font(.islandFootnote)
                .foregroundStyle(IslandPalette.textSecondary.color)
                .lineLimit(1)
            } else {
                Text(subtitle)
                    .font(.islandFootnote)
                    .foregroundStyle(IslandPalette.textSecondary.color)
                    .lineLimit(track == nil ? 2 : 1)
            }
        }
    }

    private var subtitle: String {
        guard let track else { return "Votre musique et ses commandes apparaîtront ici." }
        return track.artist.isEmpty ? (track.isPlaying ? "En lecture" : "En pause") : track.artist
    }

    private func idleAccessibilityLabel(_ idle: LastTrackModel) -> String {
        guard let last else { return "Aucune lecture. \(idle.callToAction)" }
        let artist = last.artist.isEmpty ? "" : ", \(last.artist)"
        return "Dernière lecture : \(last.title)\(artist). \(idle.callToAction)"
    }

    private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous)
        let data = track?.artworkData ?? last?.artworkJPEG
        return ZStack {
            shape.fill(IslandPalette.textPrimary.color.opacity(0.10))
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(IslandPalette.textSecondary.color)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var progressBar: some View {
        if let progress = track?.progress {
            GeometryReader { proxy in
                Rectangle().fill(IslandPalette.textPrimary.color.opacity(0.55))
                    .frame(width: proxy.size.width * IslandHUD.clamped(progress), height: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// While idle, "play" launches the player (or presses play when it is already running).
    private var playButton: some View {
        let playing = track?.isPlaying == true
        let label = playing ? "Pause" : "Lecture"
        return Button {
            if isIdle, let idle { idle.play(send: send) } else { send(.playPause) }
        } label: {
            transportImage(playing ? "pause.fill" : "play.fill")
        }
        .buttonStyle(HomeTapStyle())
        .help(isIdle ? (idle?.help ?? label) : label)
        .accessibilityLabel(label)
    }

    private func transportImage(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(IslandPalette.textPrimary.color)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
    }

    private func transportButton(_ command: HomeTransport, _ symbol: String, _ label: String) -> some View {
        Button { send(command) } label: { transportImage(symbol) }
            .buttonStyle(HomeTapStyle())
            .help(label)
            .accessibilityLabel(label)
    }
}
