import CoreGraphics
import Foundation
import Observation

/// Everything the island home needs and the user can change: size, look, round buttons, sliders, now playing.
/// Persisted in the app's defaults under the same key names the old app used for the same settings.
@MainActor @Observable
public final class HomeModel {
    enum Keys {
        static let size = "notchSize"
        static let customWidth = "notchCustomWidth"
        static let customHeight = "notchCustomHeight"
        static let translucent = "notchTranslucentBackground"
        static let outline = "notchOutlineEnabled"
        static let hideGap = "notchHideMenuBarGap"
        static let fitWidth = "notchCameraFitWidth"
        static let fitHeight = "notchCameraFitHeight"
        static let layout = "notchQuickAccessLayout"
        /// Set once the Claude round button has been offered to a layout stored by an older build.
        static let claudeShortcutSeeded = "notchClaudeShortcutSeeded"
    }

    public static let fitWidthRange: ClosedRange<Double> = -10...10
    public static let fitHeightRange: ClosedRange<Double> = -6...6
    /// Extra height when "Masquer l'espace sous l'encoche" is on: the strip under the notch disappears.
    public static let hiddenGapExtra: CGFloat = 4

    public var sizeMode: IslandSizeMode { didSet { defaults.set(sizeMode.rawValue, forKey: Keys.size) } }
    public var customWidth: Double {
        didSet {
            // @Observable re-runs didSet on assignment: only write back when clamping changed something.
            let clamped = Self.clamp(customWidth, HomeGeometry.customWidthRange)
            if clamped != customWidth { customWidth = clamped; return }
            defaults.set(customWidth, forKey: Keys.customWidth)
        }
    }
    public var customHeight: Double {
        didSet {
            // @Observable re-runs didSet on assignment: only write back when clamping changed something.
            let clamped = Self.clamp(customHeight, HomeGeometry.customHeightRange)
            if clamped != customHeight { customHeight = clamped; return }
            defaults.set(customHeight, forKey: Keys.customHeight)
        }
    }
    /// "Fond translucide": the open island blurs what is behind it instead of staying solid black.
    public var translucentBackground: Bool { didSet { defaults.set(translucentBackground, forKey: Keys.translucent) } }
    /// "Afficher le contour".
    public var showsOutline: Bool { didSet { defaults.set(showsOutline, forKey: Keys.outline) } }
    public var hidesNotchGap: Bool { didSet { defaults.set(hidesNotchGap, forKey: Keys.hideGap) } }
    public var notchFitWidth: Double {
        didSet {
            // @Observable re-runs didSet on assignment: only write back when clamping changed something.
            let clamped = Self.clamp(notchFitWidth, Self.fitWidthRange)
            if clamped != notchFitWidth { notchFitWidth = clamped; return }
            defaults.set(notchFitWidth, forKey: Keys.fitWidth)
        }
    }
    public var notchFitHeight: Double {
        didSet {
            // @Observable re-runs didSet on assignment: only write back when clamping changed something.
            let clamped = Self.clamp(notchFitHeight, Self.fitHeightRange)
            if clamped != notchFitHeight { notchFitHeight = clamped; return }
            defaults.set(notchFitHeight, forKey: Keys.fitHeight)
        }
    }
    public var buttons: HomeButtonLayout {
        didSet { if let data = buttons.encoded() { defaults.set(data, forKey: Keys.layout) } }
    }

    public let volume: HomeLevel
    public let brightness: HomeLevel
    public let keyboardLight: HomeLevel

    /// What is playing, fed by the app; nil shows "Aucune lecture". Assigning what is already there does not
    /// notify: the app feeds it from every layout the activity engine publishes, most of them unrelated.
    public var track: HomeTrack? {
        get {
            access(keyPath: \.track)
            return storedTrack
        }
        set {
            guard newValue != storedTrack else { return }
            withMutation(keyPath: \.track) { storedTrack = newValue }
        }
    }
    @ObservationIgnored private var storedTrack: HomeTrack?
    @ObservationIgnored public var transport: @MainActor (HomeTransport) -> Void

    /// Launches the Claude desktop app from the Claude shortcut.
    @ObservationIgnored public var claudeApp = ClaudeAppLauncher()

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults,
                volume: LevelBackend = SystemVolume.backend,
                brightness: LevelBackend = SystemBrightness.backend,
                keyboardLight: LevelBackend = .unsupported("Rétroéclairage du clavier : réglage non disponible"),
                transport: @escaping @MainActor (HomeTransport) -> Void = { MediaKeyPoster.post($0) }) {
        self.defaults = defaults
        sizeMode = defaults.string(forKey: Keys.size).flatMap(IslandSizeMode.init(rawValue:)) ?? .spacious
        customWidth = Self.stored(defaults, Keys.customWidth, HomeGeometry.defaultCustomWidth, HomeGeometry.customWidthRange)
        customHeight = Self.stored(defaults, Keys.customHeight, HomeGeometry.defaultCustomHeight, HomeGeometry.customHeightRange)
        translucentBackground = defaults.bool(forKey: Keys.translucent)
        showsOutline = defaults.bool(forKey: Keys.outline)
        hidesNotchGap = defaults.bool(forKey: Keys.hideGap)
        notchFitWidth = Self.stored(defaults, Keys.fitWidth, 0, Self.fitWidthRange)
        notchFitHeight = Self.stored(defaults, Keys.fitHeight, 0, Self.fitHeightRange)
        let storedLayout = defaults.data(forKey: Keys.layout)
        var layout = HomeButtonLayout.decode(storedLayout)
        if !defaults.bool(forKey: Keys.claudeShortcutSeeded) {
            // A layout saved before the Claude shortcut existed gets it once, where there is room. A user who
            // removes it afterwards keeps it removed. Same JSON shape and version, nothing else changes.
            defaults.set(true, forKey: Keys.claudeShortcutSeeded)
            if storedLayout != nil {
                layout = layout.addingClaudeShortcut()
                if let data = layout.encoded() { defaults.set(data, forKey: Keys.layout) }
            }
        }
        buttons = layout
        self.volume = HomeLevel(title: "Volume", systemImage: "speaker.wave.2.fill", backend: volume)
        self.brightness = HomeLevel(title: "Luminosité", systemImage: "sun.max.fill", backend: brightness)
        self.keyboardLight = HomeLevel(title: "Rétroéclairage du clavier", systemImage: "light.max", backend: keyboardLight)
        self.transport = transport
    }

    private static func stored(_ defaults: UserDefaults, _ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
        guard let value = defaults.object(forKey: key) as? Double, value.isFinite else { return fallback }
        return clamp(value, range)
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : range.lowerBound
    }


    /// Re-reads the three sliders (the island just opened, or a key moved a level).
    public func refreshLevels() {
        volume.refresh()
        brightness.refresh()
        keyboardLight.refresh()
    }

    /// The sliders the home shows, in order: only the levels the system lets us read.
    public var availableLevels: [HomeLevel] { [volume, brightness, keyboardLight].filter(\.isAvailable) }

    /// Why a slider is missing, for the tooltip of the sliders row. Nil when all three are there.
    public var unavailableLevelsHelp: String? {
        let missing = [volume, brightness, keyboardLight].filter { !$0.isAvailable }
        guard !missing.isEmpty else { return nil }
        return missing.map { "\($0.title) : \($0.unavailableReason)" }.joined(separator: "\n")
    }

    // MARK: - Derived sizes

    /// Solid black strip at the top of the body, behind the hardware notch.
    public var bandHeight: CGFloat {
        let h = ShellLayout.topBandHeight + CGFloat(notchFitHeight) + (hidesNotchGap ? Self.hiddenGapExtra : 0)
        return max(h, 24)
    }

    public var homeBody: CGSize {
        HomeGeometry.homeBody(mode: sizeMode, customWidth: customWidth, customHeight: customHeight, band: bandHeight)
    }

    public var tileRows: Int {
        HomeGeometry.tileRows(for: sizeMode, customHeight: customHeight, band: bandHeight)
    }

    /// Tiles of the home grid for the current size.
    public var tileActions: [HomeAction] {
        HomeActionCatalog.tileIDs.prefix(tileRows * HomeGeometry.tileColumns).compactMap(HomeActionCatalog.action)
    }

    public func panelSize(body: CGSize) -> CGSize {
        HomeGeometry.panel(body: body,
                           sideButtons: !buttons.buttons(on: .left).isEmpty || !buttons.buttons(on: .right).isEmpty,
                           bottomButtons: !buttons.buttons(on: .bottom).isEmpty)
    }
}
