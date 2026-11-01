import AppKit
import Foundation
import IslandKit
import IslandTestSupport
import IslandUI
import SwiftUI
import Testing
@testable import ShellKit

/// The now-playing card in its four states, at the Spacieuse width, as PNGs (ImageRenderer: no window is shown).
/// Look at them by hand: `$TMPDIR/mac-island-home/nowplaying-*.png`.
@MainActor
@Suite struct HomeLastTrackRenderTests {
    private func cover() -> Data {
        let size = NSSize(width: 256, height: 256)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.2, alpha: 1),
                                NSColor(calibratedRed: 0.25, green: 0.15, blue: 0.55, alpha: 1)])?.draw(in: rect, angle: 60)
            return true
        }
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])!
    }

    private func render(_ name: String, track: HomeTrack?, record: LastTrackRecord?) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mis-np-render-\(UUID().uuidString)")
        let bench = TestDefaults.make()
        defer { bench.cleanup(); try? FileManager.default.removeItem(at: folder) }
        let store = LastTrackStore(url: folder.appendingPathComponent("last-track"))
        if let record { store.save(record) }
        let launcher = FakePlayerLauncher()
        launcher.installed = ["com.spotify.client": FakePlayerLauncher.spotifyURL]
        let model = LastTrackModel(defaults: bench.defaults, store: store, launcher: launcher,
                                   now: { Date(timeIntervalSince1970: 1_700_000_000 + 2 * 3_600 + 120) })
        model.refresh()
        let width = HomeGeometry.homeBody(mode: .spacious, customWidth: 0, customHeight: 0, band: 38, tileCount: 0).width
        let view = HomeNowPlayingCard(track: track, idle: model) { _ in }
            .padding(.horizontal, IslandSpacing.l - 2)
            .frame(width: width, height: HomeGeometry.nowPlayingCard + 24)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("mac-island-home")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try png.write(to: out.appendingPathComponent("nowplaying-\(name).png"))
        #expect(png.count > 2_000)
    }

    @Test func theFourStates() throws {
        let record = LastTrackRecord(title: "Reason (Bonobo Rework)", artist: "Bonobo", album: "Migration",
                                     playerBundleID: "com.spotify.client",
                                     timestamp: Date().addingTimeInterval(-2 * 3_600 - 120), artworkJPEG: cover())
        try render("1-playing", track: HomeTrack(title: "Reason (Bonobo Rework)", artist: "Bonobo", artworkData: cover(),
                                                 isPlaying: true, progress: 0.4), record: record)
        try render("2-paused", track: HomeTrack(title: "Reason (Bonobo Rework)", artist: "Bonobo", artworkData: cover(),
                                                isPlaying: false, progress: 0.4), record: record)
        try render("3-idle-last-track", track: nil, record: record)
        try render("4-idle-empty", track: nil, record: nil)
    }
}
