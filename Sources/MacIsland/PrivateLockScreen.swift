import Darwin
import Foundation
import ShellKit

// The only file that touches a private symbol. If macOS removes it, `lock()` returns false and the
// public fallback below takes over; nothing else in the app knows about it.

/// Preferred locker: `SACLockScreenImmediate` from the private `login` framework, loaded at run time.
/// Its return value is undocumented, so the call counts as made once the symbol resolved.
struct LoginFrameworkScreenLock: ScreenLocking {
    private static let path = "/System/Library/PrivateFrameworks/login.framework/login"
    private static let symbol = "SACLockScreenImmediate"

    func lock() -> Bool {
        guard let handle = dlopen(Self.path, RTLD_LAZY) else { return false }
        defer { dlclose(handle) }
        guard let address = dlsym(handle, Self.symbol) else { return false }
        typealias LockFunction = @convention(c) () -> Int32
        _ = unsafeBitCast(address, to: LockFunction.self)()
        return true
    }
}

/// The one lock path of the app: the login framework first, `pmset displaysleepnow` when it is missing or fails.
/// The island's lock button and the ported quick toggle ("Verrouiller l'écran", `PortQuickToggles`) both end here,
/// so there is no second private lock call anywhere.
@MainActor
enum AppScreenLock {
    static func lock() -> ScreenLockOutcome {
        ScreenLockChain.lock(primary: LoginFrameworkScreenLock(), fallback: DisplaySleepScreenLock())
    }
}

/// Fallback: `pmset displaysleepnow`, fixed arguments, no shell. It sleeps the display, which locks the
/// session only when "Require password after screen saver or display sleep" is on (System Settings >
/// Lock Screen); with that setting off the screen just goes dark and stays unlocked.
struct DisplaySleepScreenLock: ScreenLocking {
    func lock() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        do { try process.run() } catch { return false }
        return true
    }
}
