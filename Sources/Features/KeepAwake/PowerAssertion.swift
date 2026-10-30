import Foundation
import IOKit.pwr_mgt

enum AssertionKind: Equatable {
    case idleSystemSleep
    case idleDisplaySleep
}

/// IOKit behind a protocol so tests can assert create/release pairing.
protocol PowerAssertionProviding: Sendable {
    func create(_ kind: AssertionKind, reason: String) -> UInt32?
    func release(_ id: UInt32)
}

struct IOKitPowerAssertions: PowerAssertionProviding {
    func create(_ kind: AssertionKind, reason: String) -> UInt32? {
        let type = kind == .idleSystemSleep
            ? kIOPMAssertionTypePreventUserIdleSystemSleep
            : kIOPMAssertionTypePreventUserIdleDisplaySleep
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &id)
        return result == kIOReturnSuccess ? id : nil
    }

    func release(_ id: UInt32) { IOPMAssertionRelease(IOPMAssertionID(id)) }
}

/// Owns assertion ids and releases them all on `releaseAll()` or deinit. Not main-actor bound,
/// so the controller's deinit can reach it.
final class AssertionSet: @unchecked Sendable {
    private let lock = NSLock()
    private let power: PowerAssertionProviding
    private var ids: [UInt32] = []

    init(power: PowerAssertionProviding) { self.power = power }
    deinit { releaseAll() }

    var isEmpty: Bool { lock.lock(); defer { lock.unlock() }; return ids.isEmpty }

    /// Creates the given kinds; on any failure releases what it made and returns false.
    func acquire(_ kinds: [AssertionKind], reason: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard ids.isEmpty else { return true }
        for kind in kinds {
            guard let id = power.create(kind, reason: reason) else {
                ids.forEach(power.release)
                ids = []
                return false
            }
            ids.append(id)
        }
        return true
    }

    func releaseAll() {
        lock.lock(); defer { lock.unlock() }
        ids.forEach(power.release)
        ids = []
    }
}
