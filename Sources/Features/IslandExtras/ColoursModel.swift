import AppKit
import Foundation
import IslandKit
import Observation

/// The "Couleurs" tab: the system eyedropper (`NSColorSampler`, no permission), the last colours picked, a click copies.
@MainActor @Observable
final class ColoursModel {
    /// Shows the system loupe and answers with the picked colour, or nil when the user cancels.
    typealias Picker = @MainActor (@escaping @MainActor (NSColor?) -> Void) -> Void

    private(set) var recent: RecentColours
    private(set) var lastCopied: String?
    private let defaults: UserDefaults
    private let picker: Picker
    private let copy: @MainActor (String) -> Void
    private var picking = false

    init(defaults: UserDefaults,
         picker: Picker? = nil,
         copy: (@MainActor (String) -> Void)? = nil) {
        self.defaults = defaults
        self.picker = picker ?? Self.systemPicker
        self.copy = copy ?? Self.copyToPasteboard
        recent = RecentColours.load(from: defaults)
    }

    var isPicking: Bool { picking }

    /// One eyedropper at a time. A picked colour goes to the top of the list and onto the pasteboard.
    func pick() {
        guard !picking else { return }
        picking = true
        picker { [weak self] color in
            guard let self else { return }
            self.picking = false
            guard let color, let hex = Self.hex(of: color) else { return }
            self.record(hex)
            self.copyHex(hex)
        }
    }

    func copyHex(_ hex: String) {
        copy(hex)
        lastCopied = hex
    }

    func record(_ hex: String) {
        recent.add(hex)
        recent.save(to: defaults)
    }

    func clear() {
        recent = RecentColours()
        recent.save(to: defaults)
        lastCopied = nil
    }

    static func hex(of color: NSColor) -> String? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        return RecentColours.hex(red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent))
    }

    // The system sampler must stay referenced while its loupe is up.
    private static var activeSampler: NSColorSampler?

    static let systemPicker: Picker = { done in
        let sampler = NSColorSampler()
        activeSampler = sampler
        sampler.show { color in
            DispatchQueue.main.async {
                activeSampler = nil
                MainActor.assumeIsolated { done(color) }
            }
        }
    }

    /// Through the app-wide general-pasteboard lane, like every other writer (never on the main thread).
    static let copyToPasteboard: @MainActor (String) -> Void = { text in
        GeneralPasteboardLane.shared.async {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }
}
