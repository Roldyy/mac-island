import Foundation
import IslandUI
import Testing
@testable import IslandKit

/// The closed strip, drawn: with the companion on, the picture differs from the one without it (something is drawn in
/// the wing), on a screen with a notch and on one without.
@MainActor
@Suite struct AmbientMascotRenderTests {
    private let clock = AmbientIndicator(id: "clock", channel: AmbientChannel.clock, symbol: "", text: "12:34", glyph: .none)
    private let battery = AmbientIndicator(id: "battery", channel: AmbientChannel.battery, symbol: "battery.75percent",
                                           text: "82%", wing: .trailing)
    private func mascot(_ wing: AmbientWing) -> AmbientIndicator {
        AmbientIndicator(id: "mascot", channel: AmbientChannel.mascot, symbol: "face.smiling", wing: wing, glyph: .mascot,
                         label: "Compagnon")
    }

    @Test func theCompanionIsDrawnInTheClosedStrip() throws {
        for notched in [true, false] {
            for wing in [AmbientWing.leading, .trailing] {
                let tag = "mascot-\(notched ? "notch" : "pill")-\(wing == .leading ? "left" : "right")"
                let without = AmbientRender.center(notched: notched, indicators: [clock, battery])
                let with = AmbientRender.center(notched: notched, indicators: [clock, battery, mascot(wing)])
                #expect(with.content.all.contains { $0.glyph == .mascot }, Comment(rawValue: tag))
                let off = try #require(AmbientRender.png(center: without, notched: notched, dark: true, name: "\(tag)-off"))
                let on = try #require(AmbientRender.png(center: with, notched: notched, dark: true, name: "\(tag)-on"))
                #expect(try Data(contentsOf: off) != Data(contentsOf: on), "\(tag): the companion draws nothing")
            }
        }
    }
}
