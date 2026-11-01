import Foundation

/// A control that really reads and writes one preference key (the migrated Vorssaint names are kept).
public struct LiveControl: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// `inverted`: the switch shows the opposite of the stored flag.
        case toggle(defaultValue: Bool, inverted: Bool)
        /// A flag stored as one of two strings (`on` or `off`).
        case stringFlag(on: String, off: String, defaultValue: Bool)
        case choice(options: [Option], defaultValue: Int)
        case stepper(range: ClosedRange<Int>, defaultValue: Int, unit: String)
        case slider(range: ClosedRange<Double>, defaultValue: Double, unit: String)
        /// A global shortcut in the stored form "option+command:9".
        case shortcut(defaultValue: String)
        /// A choice stored as one of several strings (a layout, a mode).
        case stringChoice(options: [StringOption], defaultValue: String)
        /// A button. `key` is the action id the host registered in `SettingsActions`, not a preference key.
        /// `confirm`, when set, asks once more (inline) before the action runs.
        case action(title: String, confirm: String?)
        /// A value the host reports (a count). `key` is the readout id registered in `SettingsActions`.
        case readout
    }

    public struct StringOption: Equatable, Sendable {
        public let title: String
        public let value: String
        public init(_ title: String, _ value: String) {
            self.title = title
            self.value = value
        }
    }

    public struct Option: Equatable, Sendable {
        public let title: String
        public let value: Int
        public init(_ title: String, _ value: Int) {
            self.title = title
            self.value = value
        }
    }

    public let key: String
    public let kind: Kind
    /// Only for controls that have no row in the reference page: their own title and a hint in our words.
    public let title: String?
    public let hint: String?

    public init(_ key: String, _ kind: Kind, title: String? = nil, hint: String? = nil) {
        self.key = key
        self.kind = kind
        self.title = title
        self.hint = hint
    }
}

/// Reads and writes live controls in a defaults suite. Pure on top of `UserDefaults`, so a test can
/// use a temp suite.
public struct LiveStore {
    public let defaults: UserDefaults

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func bool(_ control: LiveControl) -> Bool {
        switch control.kind {
        case let .toggle(fallback, inverted):
            // `fallback` is what the switch shows when nothing is stored yet.
            guard let stored = (defaults.object(forKey: control.key) as? NSNumber)?.boolValue else { return fallback }
            return inverted ? !stored : stored
        case let .stringFlag(on, off, fallback):
            guard let s = defaults.string(forKey: control.key) else { return fallback }
            return s == on ? true : (s == off ? false : fallback)
        default:
            return false
        }
    }

    public func setBool(_ value: Bool, _ control: LiveControl) {
        switch control.kind {
        case let .toggle(_, inverted): defaults.set(inverted ? !value : value, forKey: control.key)
        case let .stringFlag(on, off, _): defaults.set(value ? on : off, forKey: control.key)
        default: break
        }
    }

    public func int(_ control: LiveControl) -> Int {
        switch control.kind {
        case let .choice(options, fallback):
            let stored = (defaults.object(forKey: control.key) as? NSNumber)?.intValue ?? fallback
            // A stored value that is not an option still shows: the nearest option stands for it.
            return options.min { abs($0.value - stored) < abs($1.value - stored) }?.value ?? stored
        case let .stepper(range, fallback, _):
            let stored = (defaults.object(forKey: control.key) as? NSNumber)?.intValue ?? fallback
            return min(range.upperBound, max(range.lowerBound, stored))
        default:
            return 0
        }
    }

    public func setInt(_ value: Int, _ control: LiveControl) {
        if case let .stepper(range, _, _) = control.kind {
            defaults.set(min(range.upperBound, max(range.lowerBound, value)), forKey: control.key)
        } else {
            defaults.set(value, forKey: control.key)
        }
    }

    public func double(_ control: LiveControl) -> Double {
        guard case let .slider(range, fallback, _) = control.kind else { return 0 }
        let stored = (defaults.object(forKey: control.key) as? NSNumber)?.doubleValue ?? fallback
        return min(range.upperBound, max(range.lowerBound, stored))
    }

    public func setDouble(_ value: Double, _ control: LiveControl) {
        guard case let .slider(range, _, _) = control.kind else { return }
        defaults.set(min(range.upperBound, max(range.lowerBound, value)), forKey: control.key)
    }

    public func shortcut(_ control: LiveControl) -> String {
        guard case let .shortcut(fallback) = control.kind else { return "" }
        return defaults.string(forKey: control.key) ?? fallback
    }

    public func setShortcut(_ value: String, _ control: LiveControl) { defaults.set(value, forKey: control.key) }

    /// The stored string when it is one of the options; anything else (absent, garbage) reads as the default.
    public func string(_ control: LiveControl) -> String {
        guard case let .stringChoice(options, fallback) = control.kind else { return "" }
        guard let stored = defaults.string(forKey: control.key), options.contains(where: { $0.value == stored }) else {
            return fallback
        }
        return stored
    }

    public func setString(_ value: String, _ control: LiveControl) {
        guard case let .stringChoice(options, _) = control.kind, options.contains(where: { $0.value == value }) else { return }
        defaults.set(value, forKey: control.key)
    }
}
