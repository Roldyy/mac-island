import Foundation
import IslandTestSupport
@testable import PortKit

/// `PortHost`'s hooks are process-wide, and swift-testing runs suites in parallel. Every test that sets one
/// goes through `isolated`, which hands the test a temporary defaults suite (never the real preferences) and puts
/// every hook back, so no test sees another's host.
///
/// Main-actor isolation is the mutual exclusion: a synchronous body cannot interleave with another main-actor test,
/// and there is NO lock. A lock here deadlocked the suite: a background test posting
/// `UserDefaults.didChangeNotification` blocks inside `NotificationCenter.post` until the observers registered with
/// `queue: .main` have run on the main thread (`NSOperation.waitUntilFinished`), while the main thread sat in
/// `lock.lock()` held by that very poster. Tests that use this fixture must therefore be `@MainActor`.
@MainActor
enum PortHostFixture {
    static func isolated<T>(_ body: (UserDefaults) throws -> T) rethrows -> T {
        let savedDefaults = PortHost.defaults
        let savedSetEnabled = PortHost.setEnabled
        let savedStored = PortHost.storedSwitch
        let savedAvailability = PortHost.availability
        let savedPermissions = PortHost.permissionState.value
        let savedIsStored = IslandFeatureSeed.isStored
        // Fenced: a body that runs `Defaults.register` fills the fence, never the process-wide registration domain
        // (which cannot be emptied again and made every other suite read upstream's registered values as stored).
        let name = UUID().uuidString
        let bench = TestDefaults.make(name, fenced: true)
        // "Stored" = in the bench's own domain (the real profile's domain is never read by a test).
        let domain = NSTemporaryDirectory() + "mis-test-\(name)"
        IslandFeatureSeed.isStored = { defaults, key in defaults.persistentDomain(forName: domain)?[key] != nil }
        PortHost.defaults = bench.defaults
        PortHost.setEnabled = nil
        PortHost.storedSwitch = nil
        PortHost.availability = nil
        PortHost.permissionState.send(PortPermissionState())
        defer {
            PortHost.defaults = savedDefaults
            PortHost.setEnabled = savedSetEnabled
            PortHost.storedSwitch = savedStored
            PortHost.availability = savedAvailability
            PortHost.permissionState.send(savedPermissions)
            IslandFeatureSeed.isStored = savedIsStored
            bench.cleanup()
        }
        return try body(bench.defaults)
    }

    /// Reads a hook while no test is changing it.
    static func read<T>(_ body: () -> T) -> T { body() }
}

/// A `@Sendable` box for fake hooks.
final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
