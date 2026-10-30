import Foundation

/// Owned only by `FansModel`. A main-actor class cannot call main-actor code from its `deinit`
/// in Swift 6.1, so this small object carries the "manual is on" flag and sends automatic from
/// its own `deinit`, which runs when the model is released.
final class ManualReleaseGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var active = false
    private let release: @Sendable () -> Void

    init(release: @escaping @Sendable () -> Void) { self.release = release }

    var manualActive: Bool {
        get { lock.lock(); defer { lock.unlock() }; return active }
        set { lock.lock(); active = newValue; lock.unlock() }
    }

    deinit {
        if active { release() }
    }
}
