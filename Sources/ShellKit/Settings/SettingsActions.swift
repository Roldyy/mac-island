import Foundation

/// What a settings row can ask of the app: a button's action and a read-only value, both looked up by id.
/// ShellKit cannot see the feature modules, so the app delegate registers them at launch (the same shape as
/// `SettingsPageBodies`). An id nobody registered is a disabled button and an empty readout, never a crash.
@MainActor
public enum SettingsActions {
    private static var actions: [String: @MainActor () -> Void] = [:]
    private static var readouts: [String: @MainActor () -> String] = [:]

    public static func register(action id: String, _ run: @escaping @MainActor () -> Void) { actions[id] = run }
    public static func register(readout id: String, _ text: @escaping @MainActor () -> String) { readouts[id] = text }

    public static func hasAction(_ id: String) -> Bool { actions[id] != nil }
    public static func hasReadout(_ id: String) -> Bool { readouts[id] != nil }

    public static func run(_ id: String) { actions[id]?() }
    public static func readout(_ id: String) -> String { readouts[id]?() ?? "" }

    /// Removes every registration (tests).
    public static func removeAll() {
        actions.removeAll()
        readouts.removeAll()
    }
}
