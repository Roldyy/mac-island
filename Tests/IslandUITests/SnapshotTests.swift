import AppKit
import SwiftUI
import Testing
@testable import IslandUI

/// Renders each component with ImageRenderer to PNG under the temp directory (look at them by hand)
/// and checks the render is not empty. Not a pixel diff: a catch for views that collapse to nothing.
@MainActor
@Suite struct SnapshotTests {
    enum Mode: String, CaseIterable {
        case light, dark, reduceTransparency = "reduce-transparency"

        var scheme: ColorScheme { self == .light ? .light : .dark }
        var options: IslandDisplayOptions {
            self == .reduceTransparency ? IslandDisplayOptions(reduceTransparency: true) : .standard
        }
    }

    static let outputDirectory: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mac-island-snapshots")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private func render<V: View>(_ name: String, _ mode: Mode, size: CGSize = CGSize(width: 320, height: 160), @ViewBuilder _ view: () -> V) throws {
        let backdrop = mode == .light ? Color(white: 0.8) : Color(white: 0.15)
        let content = view()
            .padding(IslandSpacing.m)
            .frame(width: size.width, height: size.height)
            .background(backdrop)
            .environment(\.colorScheme, mode.scheme)
            .islandDisplayOptions(mode.options)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.nsImage, "\(name) \(mode.rawValue) : rendu vide")
        #expect(image.size.width > 0 && image.size.height > 0)
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        #expect(png.count > 500, "\(name) \(mode.rawValue) : PNG trop petit")
        try png.write(to: Self.outputDirectory.appendingPathComponent("\(name)-\(mode.rawValue).png"))
    }

    @Test func card() throws {
        for mode in Mode.allCases {
            try render("card", mode) { IslandCard { Text("Contenu de la carte").font(.islandBody) } }
        }
    }

    @Test func buttons() throws {
        for mode in Mode.allCases {
            try render("buttons", mode) {
                VStack(spacing: IslandSpacing.s) {
                    Button("Standard") {}.buttonStyle(IslandButtonStyle(.standard))
                    Button("Principal") {}.buttonStyle(IslandButtonStyle(.prominent))
                    Button("Supprimer") {}.buttonStyle(IslandButtonStyle(.destructive))
                    Button("Désactivé") {}.buttonStyle(IslandButtonStyle()).disabled(true)
                }
            }
        }
    }

    @Test func toggles() throws {
        for mode in Mode.allCases {
            try render("toggles", mode) {
                VStack(spacing: IslandSpacing.s) {
                    Toggle("Activé", isOn: .constant(true))
                    Toggle("Désactivé", isOn: .constant(false))
                }
                .toggleStyle(IslandToggleStyle())
            }
        }
    }

    @Test func headerAndRows() throws {
        for mode in Mode.allCases {
            try render("rows", mode, size: CGSize(width: 340, height: 200)) {
                VStack(alignment: .leading, spacing: IslandSpacing.s) {
                    IslandHeader("Ventilateurs", subtitle: "Deux capteurs détectés")
                    IslandRow("Température", subtitle: "Processeur", symbol: "thermometer", status: .warning) {
                        Text("72 °C").font(.islandValue)
                    }
                    IslandRow("Batterie", symbol: "battery.100", status: .success)
                }
            }
        }
    }

    @Test func emptyState() throws {
        for mode in Mode.allCases {
            try render("empty", mode, size: CGSize(width: 320, height: 200)) {
                IslandEmptyState(symbol: "tray", message: "Rien à afficher pour le moment.", actionTitle: "Actualiser") {}
            }
        }
    }

    @Test func hud() throws {
        for mode in Mode.allCases {
            try render("hud", mode, size: CGSize(width: 320, height: 80)) {
                IslandHUD(symbol: "speaker.wave.2.fill", label: "Volume", value: 0.6).islandGlass()
            }
        }
    }

    @Test func badges() throws {
        for mode in Mode.allCases {
            try render("badges", mode, size: CGSize(width: 360, height: 60)) {
                HStack {
                    ForEach(IslandStatus.allCases, id: \.self) { IslandBadge($0.label, status: $0) }
                }
            }
        }
    }

    @Test func glassSurface() throws {
        for mode in Mode.allCases {
            try render("glass", mode) {
                Text("Verre").font(.islandBody).padding(IslandSpacing.xl).islandGlass()
            }
        }
    }
}
