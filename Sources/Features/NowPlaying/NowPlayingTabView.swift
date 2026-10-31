import AppKit
import SwiftUI

struct NowPlayingTabView: View {
    @State private var model = NowPlayingFeature.model

    var body: some View {
        Group {
            switch model.access {
            case .needsAuthorization: authorizeView(message: "Autoriser l'accès à Spotify et Musique pour afficher la lecture.")
            case .denied: authorizeView(message: "Accès refusé : Réglages Système > Confidentialité > Automatisation.")
            case .ready:
                if let s = model.snapshot { player(s) } else { empty }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear { model.setVisible(true) }
        .onDisappear { model.setVisible(false) }
    }

    private var empty: some View {
        Text("Rien en lecture").font(.callout).foregroundStyle(.white.opacity(0.6))
    }

    private func authorizeView(message: String) -> some View {
        VStack(spacing: 8) {
            Text(message).font(.caption).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
            Button("Autoriser") { Task { await model.authorize() } }
                .accessibilityLabel("Autoriser l'accès aux lecteurs de musique")
        }
        .padding(12)
    }

    private func player(_ s: NowPlayingSnapshot) -> some View {
        HStack(spacing: 12) {
            cover.frame(width: 72, height: 72).clipShape(.rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 6) {
                Text(s.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                Text(s.artist).font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                ProgressView(value: s.progress ?? 0)
                    .tint(.white)
                    .accessibilityLabel("Progression")
                    .accessibilityValue(s.progress.map { "\(Int($0 * 100)) pour cent" } ?? "inconnue")
                HStack(spacing: 20) {
                    control("backward.fill", "Précédent") { model.send(.previous) }
                    control(s.isPlaying ? "pause.fill" : "play.fill", s.isPlaying ? "Pause" : "Lecture") {
                        model.send(.playPause)
                    }
                    control("forward.fill", "Suivant") { model.send(.next) }
                }
            }
        }
        .padding(12)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var cover: some View {
        if let data = model.artwork, let img = NSImage(data: data) {
            Image(nsImage: img).resizable().scaledToFill().accessibilityLabel("Pochette")
        } else {
            ZStack {
                Color.white.opacity(0.1)
                Image(systemName: "music.note").foregroundStyle(.white.opacity(0.5))
            }
            .accessibilityHidden(true)
        }
    }

    private func control(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.title3).foregroundStyle(.white) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }
}
