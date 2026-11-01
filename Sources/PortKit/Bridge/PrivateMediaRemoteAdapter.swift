// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W8A (music). New file of the lane: the app side of the MediaRemote adapter.

import Foundation

/// Why the system Now Playing session cannot be read. French, for the music page.
enum MediaRemoteUnavailableReason: Equatable {
    /// The user's kill switch (or a previous run's breaker) is on.
    case killSwitch
    /// `/usr/bin/perl` is missing: the adapter runs inside it.
    case perlMissing
    /// `now-playing.pl` is not in the app bundle (`swift run`, a bundle built without the adapter).
    case scriptMissing
    /// `libMacIslandNowPlaying.dylib` is not in `Contents/Frameworks`.
    case libraryMissing

    var message: String {
        switch self {
        case .killSwitch:
            "La lecture du système est coupée dans les réglages de sécurité. Réactivez-la pour afficher le titre en cours."
        case .perlMissing:
            "Le titre en cours ne peut pas être lu : l’outil système perl est introuvable sur ce Mac."
        case .scriptMissing, .libraryMissing:
            "Le titre en cours ne peut pas être lu : cette version de Mac Island ne contient pas le lecteur de lecture système. Lancez l’app installée, pas « swift run »."
        }
    }
}

enum MediaRemoteCapability: Equatable {
    case available(script: String, library: String)
    case unavailable(MediaRemoteUnavailableReason)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var unavailableReason: MediaRemoteUnavailableReason? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

/// What the music service needs from the platform to read the system Now Playing session: the command that
/// runs the adapter, or the reason there is none. A protocol so the music service, the tab and the tests never
/// care how the answer was found (the live one probes files, the fakes answer).
protocol MediaRemoteAdapterProviding {
    func capability() -> MediaRemoteCapability
}

extension MediaRemoteAdapterProviding {
    /// The arguments of `/usr/bin/perl`, or nil when the adapter is unavailable. Never throws, never traps:
    /// "unavailable" is an answer, and the music page says so instead of looking empty.
    func launchArguments() -> [String]? {
        guard case .available(let script, let library) = capability() else { return nil }
        return [script, library]
    }
}

/// The live probe. MediaRemote itself is a private framework and is NEVER loaded by the app: since macOS 15.4 it
/// answers only Apple-signed processes, so `Sources/NowPlayingAdapter` (a separate dynamic library, the one place
/// that touches the private symbols) is loaded into the platform binary `/usr/bin/perl` by `now-playing.pl`. This
/// type only checks that the three pieces are there and that the kill switch is off, with plain file checks.
///
/// Capability probe: perl, then the script, then the library, each one a distinct reason.
/// Kill switch: `macisland.musicAdapter.disabled` in the host's defaults (also set by the safety page). When it is
/// on, nothing is launched, and the registry's own kill switch stops the music features before that.
struct MediaRemoteAdapterLocator: MediaRemoteAdapterProviding {
    static let killSwitchKey = "macisland.musicAdapter.disabled"
    static let perlPath = "/usr/bin/perl"
    static let scriptName = "now-playing"
    static let libraryName = "libMacIslandNowPlaying.dylib"

    var isKilled: () -> Bool
    var fileExists: (String) -> Bool
    var scriptPath: () -> String?
    var libraryPath: () -> String?

    func capability() -> MediaRemoteCapability {
        if isKilled() { return .unavailable(.killSwitch) }
        guard fileExists(Self.perlPath) else { return .unavailable(.perlMissing) }
        guard let script = scriptPath(), fileExists(script) else { return .unavailable(.scriptMissing) }
        guard let library = libraryPath(), fileExists(library) else { return .unavailable(.libraryMissing) }
        return .available(script: script, library: library)
    }

    /// The command line of the perl child: `-T` first (taint mode: PERL5OPT and PERL5LIB are ignored, "." is not in
    /// @INC), no `-I`, then the script, the library and the mode.
    static func perlArguments(adapter: [String], mode: String) -> [String] {
        ["-T"] + adapter + [mode]
    }

    /// The environment of the perl child, built from scratch: a fixed PATH, and HOME, TMPDIR and LANG taken from `base`
    /// (with a safe fallback). Everything else the app inherited (PERL5OPT, PERL5LIB, DYLD_*, tokens) stops here.
    static func childEnvironment(from base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        func value(_ key: String, fallback: String) -> String {
            guard let v = base[key], !v.isEmpty, !v.contains("\0") else { return fallback }
            return v
        }
        return [
            "PATH": "/usr/bin:/bin",
            "HOME": value("HOME", fallback: NSHomeDirectory()),
            "TMPDIR": value("TMPDIR", fallback: NSTemporaryDirectory()),
            "LANG": value("LANG", fallback: "en_US.UTF-8")
        ]
    }

    static var live: MediaRemoteAdapterLocator {
        MediaRemoteAdapterLocator(
            isKilled: { PortHost.defaults.bool(forKey: killSwitchKey) },
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            scriptPath: { Bundle.main.url(forResource: scriptName, withExtension: "pl")?.path },
            libraryPath: { Bundle.main.privateFrameworksURL?.appendingPathComponent(libraryName).path })
    }
}
