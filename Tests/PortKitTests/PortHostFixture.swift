import Foundation
import IslandTestSupport
@testable import PortKit

/// `PortHost`'s hooks are process-wide, and swift-testing runs suites in parallel. Every test that sets one
/// goes through `isolated`, which holds one lock, hands the test a temporary defaults suite (never the real
/// preferences) and puts every hook back, so no test sees another's host.
enum PortHostFixture {
    private static let lock = NSRecursiveLock()

    static func isolated<T>(_ body: (UserDefaults) throws -> T) rethrows -> T {
        lock.lock()
        let savedDefaults = PortHost.defaults
        let savedSetEnabled = PortHost.setEnabled
        let savedStored = PortHost.storedSwitch
        let savedAvailability = PortHost.availability
        let savedPermissions = PortHost.permissionState.value
        let bench = TestDefaults.make()
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
            bench.cleanup()
            lock.unlock()
        }
        return try body(bench.defaults)
    }

    /// Reads a hook while no test is changing it.
    static func read<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
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
