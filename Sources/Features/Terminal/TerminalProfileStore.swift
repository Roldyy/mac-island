import Foundation
import IslandKit

/// Reads and writes the profile library in the app's defaults (key `terminalColorProfile`, versioned JSON).
struct TerminalProfileStore {
    static let key = "terminalColorProfile"

    private let defaults: UserDefaults

    private let maxBytes: Int

    init(defaults: UserDefaults, maxBytes: Int = TerminalProfileLibraryCodec.maxBytes) {
        self.defaults = defaults
        self.maxBytes = maxBytes
    }

    /// The store the app uses.
    static func standard() -> TerminalProfileStore { TerminalProfileStore(defaults: AppDefaults.make() ?? .standard) }

    func load() -> TerminalProfileLibrary {
        TerminalProfileLibraryCodec.decode(defaults.data(forKey: Self.key), maxBytes: maxBytes)
    }

    /// False when the library cannot be written (too large to be read back): what is stored stays untouched.
    @discardableResult
    func save(_ library: TerminalProfileLibrary) -> Bool {
        guard let data = TerminalProfileLibraryCodec.encode(library, maxBytes: maxBytes) else { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }

    /// The profile a terminal starting now must wear (nil: the default theme).
    var activeProfile: TerminalColorProfile? { load().active }
}
