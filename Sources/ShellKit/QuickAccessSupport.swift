import Foundation
import IslandKit

/// Locks the screen. Implemented in the app target (one private-API file, one public-tool fallback).
@MainActor
public protocol ScreenLocking {
    /// True when the request was made. Never throws, never prompts.
    func lock() -> Bool
}

public enum ScreenLockOutcome: Equatable, Sendable {
    case locked, lockedByFallback, failed
}

public enum ScreenLockChain {
    /// The preferred locker first; the fallback only when it is missing or reports failure.
    @MainActor
    public static func lock(primary: ScreenLocking?, fallback: ScreenLocking) -> ScreenLockOutcome {
        if let primary, primary.lock() { return .locked }
        return fallback.lock() ? .lockedByFallback : .failed
    }
}

/// Where a screenshot goes and what the user is told. Pure, so the quick action stays thin.
public enum ScreenshotPlan {
    /// `/usr/bin/screencapture`: interactive area selection, PNG, written to `file`. Fixed arguments, no shell.
    public static func arguments(file: URL) -> [String] { ["-i", "-t", "png", file.path] }

    public static func fileName(date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Capture Mac Island \(f.string(from: date)).png"
    }

    /// A name that does not overwrite anything: " 2", " 3"... before the extension when taken.
    public static func destination(in directory: URL, date: Date, timeZone: TimeZone = .current,
                                   exists: (URL) -> Bool) -> URL {
        let name = fileName(date: date, timeZone: timeZone)
        var candidate = directory.appendingPathComponent(name)
        var n = 2
        let stem = (name as NSString).deletingPathExtension
        while exists(candidate) {
            candidate = directory.appendingPathComponent("\(stem) \(n).png")
            n += 1
        }
        return candidate
    }
}

/// The short French lines shown in the closed island after a quick action.
public enum QuickActionNotice {
    public static func permission(_ permission: FeaturePermission) -> String { "Accès requis : \(permission.title)" }
    public static let inputMonitoring = "Accès requis : Surveillance de l'entrée"
    /// Plain paste could not post its Cmd+V. The Clipboard feature cannot import ShellKit and keeps this same
    /// wording in `PlainPasteNotice.needsPermission`.
    public static let pastePlainNeedsAccess = "Autorisation requise : Surveillance de l'entrée / Accessibilité"
    public static let captureDone = "Capture copiée et enregistrée"
    public static let captureFailed = "Capture impossible"
    public static let lockFailed = "Verrouillage impossible"
    public static let cleaningRefused = "Nettoyage refusé par macOS"
    public static let cleaningOff = "Mode nettoyage désactivé : activez-le dans Fonctions"
}
