import AppKit
import SwiftUI
import Testing
@testable import IslandUI

/// Renders each component with ImageRenderer to PNG under the temp directory (look at them by hand).
/// Not a pixel diff against a golden: it renders the backdrop alone and the component on the same
/// backdrop, and the component must change at least `minimumChangedPixels` of them. A view that
/// collapses to nothing (or draws in the backdrop's own color) fails.
@MainActor
@Suite struct SnapshotTests {
    enum Mode: String, CaseIterable {
        case light, dark
        case reduceTransparency = "reduce-transparency"
        case lightReduceTransparency = "light-reduce-transparency"
        case increaseContrast = "increase-contrast"
        /// The island's own look: black behind the notch, always the dark scheme.
        case notch

        var scheme: ColorScheme {
            switch self {
            case .light, .lightReduceTransparency: .light
            default: .dark
            }
        }

        var options: IslandDisplayOptions {
            switch self {
            case .reduceTransparency, .lightReduceTransparency: IslandDisplayOptions(reduceTransparency: true)
            case .increaseContrast: IslandDisplayOptions(increaseContrast: true)
            default: .standard
            }
        }

        var backdrop: Color {
            switch self {
            case .light, .lightReduceTransparency: Color(white: 0.8)
            case .notch: IslandSurface.notchBlack
            default: Color(white: 0.15)
            }
        }
    }

    /// A text line at 2x is already several hundred pixels; this only has to separate "drawn" from "empty".
    static let minimumChangedPixels = 150

    static let outputDirectory: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mac-island-snapshots")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    // MARK: rendering helpers

    private func environment<V: View>(_ view: V, _ mode: Mode, size: CGSize) -> some View {
        view
            .frame(width: size.width, height: size.height)
            .background(mode.backdrop)
            .environment(\.colorScheme, mode.scheme)
            .islandDisplayOptions(mode.options)
    }

    private func cgImage<V: View>(_ view: V) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.cgImage
    }

    /// RGBA8 in sRGB, so two renders compare byte for byte whatever color space the renderer picked.
    static func pixels(_ image: CGImage) -> [UInt8]? {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? data : nil
    }

    /// Pixels where any channel moved by more than a few levels (anti-aliasing noise stays below it).
    static func changedPixels(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return max(a.count, b.count) / 4 }
        var changed = 0
        var i = 0
        while i < a.count {
            let delta = max(abs(Int(a[i]) - Int(b[i])), abs(Int(a[i + 1]) - Int(b[i + 1])), abs(Int(a[i + 2]) - Int(b[i + 2])))
            if delta > 8 { changed += 1 }
            i += 4
        }
        return changed
    }

    private func render<V: View>(
        _ name: String, _ mode: Mode, size: CGSize = CGSize(width: 320, height: 160), @ViewBuilder _ view: () -> V
    ) throws {
        let label = "\(name) \(mode.rawValue)"
        let withComponent = environment(view().padding(IslandSpacing.m), mode, size: size)
        let backdropOnly = environment(Color.clear, mode, size: size)

        let image = try #require(cgImage(withComponent), "\(label) : rendu vide")
        let empty = try #require(cgImage(backdropOnly), "\(label) : fond introuvable")
        #expect(image.width > 0 && image.height > 0)
        let imagePixels = try #require(Self.pixels(image))
        let emptyPixels = try #require(Self.pixels(empty))
        let changed = Self.changedPixels(imagePixels, emptyPixels)
        #expect(changed >= Self.minimumChangedPixels, "\(label) : le composant ne dessine rien (\(changed) pixels modifiés)")

        let rep = NSBitmapImageRep(cgImage: image)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        #expect(png.count > 500, "\(label) : PNG trop petit")
        try png.write(to: Self.outputDirectory.appendingPathComponent("\(name)-\(mode.rawValue).png"))
    }

    // MARK: the check itself

    @Test func anEmptyComponentFails() throws {
        let size = CGSize(width: 120, height: 60)
        func render<V: View>(_ view: V) throws -> [UInt8] {
            let image = try #require(cgImage(environment(view, .dark, size: size)))
            return try #require(Self.pixels(image))
        }
        let base = try render(Color.clear)
        let empty = try render(Color.clear.padding(IslandSpacing.m))
        let drawn = try render(Text("Bonjour").font(.islandBody).padding(IslandSpacing.m))
        #expect(Self.changedPixels(base, empty) < Self.minimumChangedPixels)
        #expect(Self.changedPixels(base, drawn) >= Self.minimumChangedPixels)
    }

    // MARK: components

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
            try render("badges", mode, size: CGSize(width: 420, height: 60)) {
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
