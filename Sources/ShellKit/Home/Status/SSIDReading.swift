import Foundation

/// Where the Location permission stands, reduced to what the Wi-Fi name needs.
public enum LocationAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    /// Refused, restricted by a profile, or Location Services off: all mean "no name, no nag".
    case denied
}

/// The door to the system for the Wi-Fi name: the live one talks to CoreLocation and CoreWLAN, a test brings a fake.
///
/// The permission side lives on the main actor (the manager, the prompt, the cached answer). `readSSID()` is
/// `nonisolated` and the reader `Sendable`: CoreWLAN blocks, so the Network chip calls it inside its detached tick.
@MainActor
public protocol SSIDReading: AnyObject, Sendable {
    /// The cached permission answer: no system call, safe to read on every tick.
    var authorization: LocationAuthorization { get }
    /// The raw network name, nil when not on Wi-Fi or when the system hides it. Callable from any thread.
    nonisolated func readSSID() -> String?
    /// Raises the system prompt (only meaningful while `notDetermined`).
    func requestAuthorization()
    /// Called on the main actor each time the authorization changed.
    var onAuthorizationChange: (@MainActor () -> Void)? { get set }
}
