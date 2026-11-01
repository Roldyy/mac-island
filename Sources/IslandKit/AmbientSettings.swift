import Foundation

/// Preference keys of the closed island. All start with `notchIdle`; the per-channel switches are plain
/// booleans, so a Settings page can bind them with its ordinary toggle control.
public enum ClosedIslandKeys {
    /// Written by the older build: "agents", "none", and (by other versions) "music" or "battery".
    public static let legacyContent = "notchIdleContent"
    public static let order = "notchIdleOrder"
    public static let rotates = "notchIdleRotates"
    public static let perWing = "notchIdlePerWing"
    /// 0 follows the system, 12 or 24 forces the hour cycle of the clock.
    public static let clockHours = "notchIdleClockHours"
    /// Set once the older value has been carried over.
    public static let migrated = "notchIdleIndicatorsMigrated"

    public static func show(_ channel: String) -> String {
        switch channel {
        case AmbientChannel.limits: "notchIdleShowLimits"
        case AmbientChannel.claude: "notchIdleShowClaude"
        case AmbientChannel.music: "notchIdleShowMusic"
        case AmbientChannel.battery: "notchIdleShowBattery"
        case AmbientChannel.keepAwake: "notchIdleShowKeepAwake"
        default: "notchIdleShow" + channel.prefix(1).uppercased() + channel.dropFirst()
        }
    }

    public static let all = [legacyContent, order, rotates, perWing, clockHours, migrated] + AmbientChannel.userChoices.map(show)
}

/// Hour cycle of the clock: the system's (from the locale) unless the user forces one.
public enum ClockHours: Int, Equatable, Sendable {
    case system = 0
    case h12 = 12
    case h24 = 24
}

/// What the user chose for the closed island: which indicators, in which order, whether they rotate and
/// how many fit beside each side of the notch. Pure value; `ClosedIslandPreferences` persists it.
public struct ClosedIslandSettings: Equatable, Sendable {
    public static let perWingRange = 1...2
    public static let defaultRotates = true
    public static let defaultPerWing = 2

    public var enabled: Set<String>
    public var order: [String]
    public var rotates: Bool
    public var maxPerWing: Int
    public var clockHours: ClockHours

    public init(enabled: Set<String> = AmbientChannel.defaultOn, order: [String] = AmbientChannel.userChoices,
                rotates: Bool = ClosedIslandSettings.defaultRotates, maxPerWing: Int = ClosedIslandSettings.defaultPerWing,
                clockHours: ClockHours = .system) {
        self.enabled = enabled
        self.order = order
        self.rotates = rotates
        self.maxPerWing = min(max(maxPerWing, Self.perWingRange.lowerBound), Self.perWingRange.upperBound)
        self.clockHours = clockHours
    }

    public static let standard = ClosedIslandSettings()

    /// A channel the user cannot switch (alerts) is always on.
    public func isEnabled(_ channel: String) -> Bool {
        !AmbientChannel.userChoices.contains(channel) || enabled.contains(channel)
    }

    /// Position used to break a tie between two indicators of the same priority. Channels that are not in
    /// the stored order follow it in their default order; alerts come last.
    public func orderIndex(_ channel: String) -> Int {
        if let index = order.firstIndex(of: channel) { return index }
        if let index = AmbientChannel.userChoices.firstIndex(of: channel) { return order.count + index }
        return Int.max
    }

    /// Every user-facing channel, in the user's order (stored order first, then the rest).
    public var orderedChannels: [String] {
        var seen = Set<String>()
        let known = Set(AmbientChannel.userChoices)
        return (order.filter(known.contains) + AmbientChannel.userChoices).filter { seen.insert($0).inserted }
    }

    // MARK: - Migration of `notchIdleContent`

    /// The older single choice, carried over. No value (or one this build does not know) is a fresh start
    /// with everything on. "none" keeps the user's "nothing at rest": the at-rest indicators (limits,
    /// battery, keep awake) go off, the live ones (Claude, music) stay because the old build showed them too.
    public static func migrated(legacyContent: String?) -> ClosedIslandSettings {
        let live: Set<String> = [AmbientChannel.claude, AmbientChannel.music]
        // The indicators this build added are on by default unless the old choice was "nothing at rest".
        let added: Set<String> = [AmbientChannel.clock, AmbientChannel.system, AmbientChannel.network]
        switch legacyContent {
        case "none":
            return ClosedIslandSettings(enabled: live)
        case "battery":
            return ClosedIslandSettings(
                enabled: live.union([AmbientChannel.battery, AmbientChannel.keepAwake]).union(added),
                order: [AmbientChannel.battery, AmbientChannel.claude, AmbientChannel.music, AmbientChannel.keepAwake, AmbientChannel.limits])
        case "music":
            return ClosedIslandSettings(
                enabled: live.union([AmbientChannel.keepAwake]).union(added),
                order: [AmbientChannel.music, AmbientChannel.claude, AmbientChannel.keepAwake, AmbientChannel.limits, AmbientChannel.battery])
        default:  // "agents", nil, anything else
            return .standard
        }
    }

    // MARK: - Persistence

    /// Reads the stored choices. The first time (no marker) it carries `notchIdleContent` over and writes
    /// every key, so a Settings toggle bound to one of them shows what the island does.
    public static func load(from defaults: UserDefaults) -> ClosedIslandSettings {
        if !defaults.bool(forKey: ClosedIslandKeys.migrated) {
            let carried = migrated(legacyContent: defaults.string(forKey: ClosedIslandKeys.legacyContent))
            carried.write(to: defaults)
            defaults.set(true, forKey: ClosedIslandKeys.migrated)
            return carried
        }
        return read(from: defaults)
    }

    /// Pure read, never writes: missing keys fall back to the defaults.
    public static func read(from defaults: UserDefaults) -> ClosedIslandSettings {
        var enabled = Set<String>()
        for channel in AmbientChannel.userChoices {
            let key = ClosedIslandKeys.show(channel)
            // A key never written (a channel this build added) takes the channel's default; a stored choice wins.
            let isOn = defaults.object(forKey: key) == nil ? AmbientChannel.defaultOn.contains(channel) : defaults.bool(forKey: key)
            if isOn { enabled.insert(channel) }
        }
        let order = (defaults.array(forKey: ClosedIslandKeys.order) as? [String]) ?? AmbientChannel.userChoices
        let rotates = defaults.object(forKey: ClosedIslandKeys.rotates) as? Bool ?? defaultRotates
        let perWing = defaults.object(forKey: ClosedIslandKeys.perWing) as? Int ?? defaultPerWing
        let hours = (defaults.object(forKey: ClosedIslandKeys.clockHours) as? Int).flatMap(ClockHours.init(rawValue:)) ?? .system
        return ClosedIslandSettings(enabled: enabled, order: order, rotates: rotates, maxPerWing: perWing, clockHours: hours)
    }

    public func write(to defaults: UserDefaults) {
        for channel in AmbientChannel.userChoices {
            defaults.set(enabled.contains(channel), forKey: ClosedIslandKeys.show(channel))
        }
        defaults.set(order, forKey: ClosedIslandKeys.order)
        defaults.set(rotates, forKey: ClosedIslandKeys.rotates)
        defaults.set(maxPerWing, forKey: ClosedIslandKeys.perWing)
        defaults.set(clockHours.rawValue, forKey: ClosedIslandKeys.clockHours)
    }
}

/// Observable home of the settings, for the engine and for a Settings page. It follows the defaults, so a
/// toggle bound to a `notchIdle...` key (or a call below) reaches the island at once.
@MainActor
public final class ClosedIslandPreferences: ObservableObject {
    public struct Row: Identifiable, Equatable, Sendable {
        public let channel: String
        public let title: String
        public let hint: String
        public let isOn: Bool
        public var id: String { channel }
    }

    public static let shared = ClosedIslandPreferences(defaults: AppDefaults.make() ?? .standard)

    @Published public private(set) var settings: ClosedIslandSettings
    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        settings = ClosedIslandSettings.load(from: defaults)
        // Any thread may write defaults; every write is re-read on the main queue and published only if it changed.
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// True while `commit` writes its keys. `didChangeNotification` is delivered inline when the write happens on
    /// the main thread, so a reload in the middle of the write would read a half-written state and publish it:
    /// every Settings toggle would flash an intermediate state, and the samplers would start and stop for it.
    private var isWriting = false

    public func reload() {
        guard !isWriting else { return }
        let fresh = ClosedIslandSettings.read(from: defaults)
        if fresh != settings { settings = fresh }
    }

    // MARK: - Settings-side binding

    /// One row per user-facing channel, in the user's order: what a Settings list shows.
    public var rows: [Row] {
        settings.orderedChannels.map {
            Row(channel: $0, title: AmbientChannel.title($0), hint: AmbientChannel.hint($0), isOn: settings.isEnabled($0))
        }
    }

    public func setEnabled(_ channel: String, _ on: Bool) {
        guard AmbientChannel.userChoices.contains(channel) else { return }
        var next = settings
        if on { next.enabled.insert(channel) } else { next.enabled.remove(channel) }
        commit(next)
    }

    /// Moves a channel up (negative) or down (positive) in the order, within bounds.
    public func move(_ channel: String, by offset: Int) {
        var channels = settings.orderedChannels
        guard let from = channels.firstIndex(of: channel) else { return }
        let to = min(max(from + offset, 0), channels.count - 1)
        guard to != from else { return }
        channels.insert(channels.remove(at: from), at: to)
        var next = settings
        next.order = channels
        commit(next)
    }

    public func setRotates(_ on: Bool) {
        var next = settings
        next.rotates = on
        commit(next)
    }

    public func setMaxPerWing(_ count: Int) {
        var next = settings
        next.maxPerWing = min(max(count, ClosedIslandSettings.perWingRange.lowerBound), ClosedIslandSettings.perWingRange.upperBound)
        commit(next)
    }

    public func setClockHours(_ hours: ClockHours) {
        var next = settings
        next.clockHours = hours
        commit(next)
    }

    private func commit(_ next: ClosedIslandSettings) {
        guard next != settings else { return }
        isWriting = true
        defer { isWriting = false }
        settings = next
        next.write(to: defaults)
    }
}
