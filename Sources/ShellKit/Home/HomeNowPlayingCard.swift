import AppKit
import IslandUI
import SwiftUI

/// Artwork, title, artist and the three transport buttons. The live track (playing or paused) comes first.
/// With no track: a notice when a player is open (permission to give, nothing loaded), otherwise a call to
/// action: the last track (dimmed) when one is kept, "Ouvrir Spotify" otherwise; a click opens the player.
struct HomeNowPlayingCard: View {
    let track: HomeTrack?
    /// The kept last track and the player launcher; nil keeps the plain empty state.
    var idle: LastTrackModel?
    /// Why there is no track although a player is open.
    var notice: HomeNowPlayingNotice?
    /// The "Autoriser" button of the permission notice.
    var authorize: () -> Void = {}
    let send: (HomeTransport) -> Void

    private var isIdle: Bool { track == nil && notice == nil && idle != nil }
    private var last: LastTrackRecord? { isIdle ? idle?.record : nil }
    private var permissionNotice: (player: String, denied: Bool)? {
        if track == nil, case .permission(let player, let denied)? = notice { return (player, denied) }
        return nil
    }

    var body: some View {
        HStack(spacing: IslandSpacing.m) {
            if let permission = permissionNotice {
                Button { authorize() } label: { info }
                    .buttonStyle(HomeTapStyle())
                    .help(permission.denied ? "Ouvrir Réglages Système > Confidentialité > Automatisation"
                                            : "Autoriser Mac Island à contrôler \(permission.player)")
                    .accessibilityLabel(permissionAccessibilityLabel(permission))
            } else if isIdle, let idle {
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
            if let permission = permissionNotice { permissionButton(denied: permission.denied) }
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
        } else if let permission = permissionNotice {
            Text("Autoriser le contrôle de \(permission.player)")
                .font(.islandBodyEmphasis)
                .foregroundStyle(IslandPalette.textPrimary.color)
                .lineLimit(1)
            Text(permission.denied ? "Accès refusé : Automatisation." : "Pour afficher la lecture.")
                .font(.islandFootnote)
                .foregroundStyle(IslandPalette.textSecondary.color)
                .lineLimit(1)
        } else {
            Text(track?.title ?? (notice == nil ? "Aucune lecture" : "Rien en lecture"))
                .font(.islandBodyEmphasis)
                .foregroundStyle(IslandPalette.textPrimary.color)
                .lineLimit(1)
            if track == nil, notice == nil, let idle {
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
        guard let track else {
            if case .playerEmpty(let player)? = notice { return "\(player) est ouvert. Lancez un morceau." }
            return "Votre musique et ses commandes apparaîtront ici."
        }
        if track.isPlaying { return track.artist.isEmpty ? "En lecture" : track.artist }
        return track.artist.isEmpty ? "En pause" : "En pause · \(track.artist)"
    }

    private func permissionButton(denied: Bool) -> some View {
        Text(denied ? "Réglages" : "Autoriser")
            .font(.islandFootnote)
            .foregroundStyle(IslandPalette.textPrimary.color)
            .padding(.horizontal, IslandSpacing.m)
            .padding(.vertical, IslandSpacing.xs)
            .background(IslandPalette.textPrimary.color.opacity(0.16), in: Capsule())
    }

    private func permissionAccessibilityLabel(_ permission: (player: String, denied: Bool)) -> String {
        permission.denied
            ? "Accès à \(permission.player) refusé. Ouvrir les réglages d’automatisation."
            : "Autoriser le contrôle de \(permission.player)"
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
