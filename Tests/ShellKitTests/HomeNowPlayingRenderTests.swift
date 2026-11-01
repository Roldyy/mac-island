import AppKit
import Foundation
import IslandTestSupport
import IslandUI
import SwiftUI
import Testing
@testable import ShellKit

/// The card in the states the live feed produces, as PNGs (ImageRenderer: no window is shown).
/// Look at them by hand: `$TMPDIR/mac-island-home/live-*.png`.
@MainActor
@Suite struct HomeNowPlayingRenderTests {
    private func cover() -> Data {
        let image = NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
            NSGradient(colors: [NSColor(calibratedRed: 0.1, green: 0.7, blue: 0.4, alpha: 1),
                                NSColor(calibratedRed: 0.05, green: 0.2, blue: 0.3, alpha: 1)])?.draw(in: rect, angle: 60)
            return true
        }
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])!
    }

    private func render(_ name: String, reading: HomeNowPlayingReading, record: LastTrackRecord?) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mis-live-render-\(UUID().uuidString)")
        let bench = TestDefaults.make()
        defer { bench.cleanup(); try? FileManager.default.removeItem(at: folder) }
        let store = LastTrackStore(url: folder.appendingPathComponent("last-track"))
        if let record { store.save(record) }
        let launcher = FakePlayerLauncher()
        launcher.installed = ["com.spotify.client": FakePlayerLauncher.spotifyURL]
        let last = LastTrackModel(defaults: bench.defaults, store: store, launcher: launcher,
                                  now: { Date(timeIntervalSince1970: 1_700_000_000 + 2 * 3_600 + 120) })
        last.refresh()
        let state = HomeNowPlayingState.resolve(reading)
        let width = HomeGeometry.homeBody(mode: .spacious, customWidth: 0, customHeight: 0, band: 38, tileCount: 0).width
        let view = HomeNowPlayingCard(track: state.track, idle: last, notice: state.notice, authorize: {}) { _ in }
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
        try png.write(to: out.appendingPathComponent("live-\(name).png"))
        #expect(png.count > 2_000)
    }

    @Test func theLiveStates() throws {
        let spotify = HomeNowPlayingReading.Player(bundleID: "com.spotify.client", name: "Spotify")
        func playing(_ isPlaying: Bool) -> HomeTrack {
            HomeTrack(title: "Reason (Bonobo Rework)", artist: "Bonobo", artworkData: cover(), isPlaying: isPlaying,
                      progress: 0.4, album: "Migration", position: 120, duration: 300,
                      playerBundleID: spotify.bundleID, playerName: "Spotify")
        }
        let record = LastTrackRecord(title: "Stored last track", artist: "Khruangbin", album: "Mordechai",
                                     playerBundleID: "com.spotify.client",
                                     timestamp: Date(timeIntervalSince1970: 1_700_000_000), artworkJPEG: cover())
        try render("1-playing", reading: .init(access: .ready, track: playing(true), runningPlayer: spotify), record: record)
        try render("2-paused", reading: .init(access: .ready, track: playing(false), runningPlayer: spotify), record: record)
        try render("3-stopped-stored-last", reading: .init(access: .ready), record: record)
        try render("4-player-open-nothing-loaded", reading: .init(access: .ready, runningPlayer: spotify), record: record)
        try render("5-permission", reading: .init(access: .needsAuthorization, runningPlayer: spotify), record: record)
        try render("6-permission-denied", reading: .init(access: .denied, runningPlayer: spotify), record: record)
    }
}
