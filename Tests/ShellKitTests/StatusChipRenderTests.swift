import AppKit
import Foundation
import IslandUI
import SwiftUI
import Testing
@testable import ShellKit

/// The chip row in its states, as PNGs (ImageRenderer: no window is shown).
/// Look at them by hand: `$TMPDIR/mac-island-home/status-chips-*.png`.
@MainActor
@Suite struct StatusChipRenderTests {
    private func render(_ name: String, readings: [StatusChipReading], isEnabled: Bool = true) throws -> Int {
        let sources = readings.map { FakeStatusChipSource($0.kind, first: $0) }
        let feed = StatusChipFeed(sources: sources, layout: StatusChipLayout(kinds: readings.map(\.kind)), isEnabled: isEnabled)
        feed.start()
        defer { feed.stop() }
        let width = HomeGeometry.homeBody(mode: .spacious, customWidth: 0, customHeight: 0, band: 38, tileCount: 0).width
        // The strip alone: a scroll view's content does not render through ImageRenderer.
        let view = StatusChipStrip(readings: feed.readings)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, IslandSpacing.l - 2)
            .frame(width: width, height: HomeGeometry.statusChipRow + 16)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("mac-island-home")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try png.write(to: out.appendingPathComponent("status-chips-\(name).png"))
        return png.count
    }

    private var everyState: [StatusChipReading] {
        [
            StatusChipReading(kind: .network, primary: "Wi-Fi", secondary: "↓ 1,23 Mo/s  ↑ 80 Ko/s", symbol: "wifi",
                              actions: [StatusChipAction(title: "Ouvrir le Moniteur") {}]),
            StatusChipReading(kind: .load, primary: "CPU 80 %", secondary: "RAM 61 % · 62 °C", level: .attention),
            StatusChipReading(kind: .disk, primary: "9,2 Go", secondary: "libres", level: .alert),
            StatusChipReading(kind: .timer, primary: "12:30", secondary: "Pâtes", progress: 0.4,
                              actions: [StatusChipAction(title: "Pause") {}]),
        ]
    }

    /// The flat black canvas: any PNG with a capsule on it is bigger.
    private func blank() throws -> Int { try render("0-blank", readings: []) }

    @Test func theRowRendersEveryLevelAndTheProgressRing() throws {
        let size = try render("1-all-levels", readings: everyState)
        #expect(size > (try blank()) + 1_000)
    }

    @Test func aSingleChipAndAnOfflineChipRender() throws {
        let base = try blank()
        #expect(try render("2-one", readings: [StatusChipReading(kind: .network, primary: "Ethernet", symbol: "cable.connector.horizontal")]) > base)
        #expect(try render("3-offline", readings: [StatusChipReading(kind: .network, primary: "Hors ligne", symbol: "wifi.slash", level: .alert)]) > base)
    }

    @Test func aRowWithNothingToShowIsEmptyOfChips() throws {
        let empty = try render("4-empty", readings: [])
        let some = try render("5-two", readings: Array(everyState.prefix(2)))
        // Same canvas: the empty row is a flat black PNG, smaller than one with capsules.
        #expect(empty < some)
        let switchedOff = try render("6-switch-off", readings: everyState, isEnabled: false)
        #expect(switchedOff == empty)
    }

    @Test func theChipHeightFitsItsRowAndTheTypeIsLegible() {
        #expect(StatusChipView.height <= HomeGeometry.statusChipRow)
        #expect(HomeGeometry.statusChipSpace == HomeGeometry.statusChipRow + HomeGeometry.gap)
        #expect(IslandType.footnote >= IslandType.minimumSize)
    }
}
