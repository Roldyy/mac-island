import AppKit
import IslandUI
import SwiftUI

/// Artwork, title, artist and the three transport buttons. Empty state when nothing plays.
struct HomeNowPlayingCard: View {
    let track: HomeTrack?
    let send: (HomeTransport) -> Void

    var body: some View {
        HStack(spacing: IslandSpacing.m) {
            artwork
            VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
                Text(track?.title ?? "Aucune lecture")
                    .font(.islandBodyEmphasis)
                    .foregroundStyle(IslandPalette.textPrimary.color)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.islandFootnote)
                    .foregroundStyle(IslandPalette.textSecondary.color)
                    .lineLimit(track == nil ? 2 : 1)
            }
            Spacer(minLength: IslandSpacing.s)
            HStack(spacing: IslandSpacing.xs) {
                transportButton(.previous, "backward.fill", "Morceau précédent")
                transportButton(.playPause, track?.isPlaying == true ? "pause.fill" : "play.fill",
                                track?.isPlaying == true ? "Pause" : "Lecture")
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

    private var subtitle: String {
        guard let track else { return "Votre musique et ses commandes apparaîtront ici." }
        return track.artist.isEmpty ? (track.isPlaying ? "En lecture" : "En pause") : track.artist
    }

    private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous)
        return ZStack {
            shape.fill(IslandPalette.textPrimary.color.opacity(0.10))
            if let data = track?.artworkData, let image = NSImage(data: data) {
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

    private func transportButton(_ command: HomeTransport, _ symbol: String, _ label: String) -> some View {
        Button { send(command) } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(IslandPalette.textPrimary.color)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(HomeTapStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}
