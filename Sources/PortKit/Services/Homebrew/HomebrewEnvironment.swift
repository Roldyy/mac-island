// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

/// The environment `brew` runs with. An app launched from Finder gets launchd's
/// environment, not the one a Terminal has after `~/.zprofile`, so a proxy or a
/// mirror exported there never reached the brew this app runs (issue #1290).
/// The login shell is asked once per launch for its exports, and only the names
/// brew itself keeps (the filter in `bin/brew`) are handed on.
enum HomebrewEnvironment {
    /// Mac Island: the environment `brew` runs with, built WITHOUT starting a shell. Upstream asked the login
    /// shell (`-l -i -c`) for its exports, which runs the person's `~/.zprofile` and `~/.zshrc` in our name and
    /// hands every variable of the app to brew and to the casks' scripts. Here only a short allowlist of the
    /// app's own variables goes through, plus brew's own proxy and `HOMEBREW_*` names, with a fixed `PATH`.
    /// A proxy that is only exported in a shell startup file no longer reaches brew: set it in the app's
    /// environment or as `HOMEBREW_*` instead.
    static let forBrew: [String: String] = environment(from: ProcessInfo.processInfo.environment)

    /// The one `PATH` brew runs with: the two Homebrew prefixes, then the system directories.
    static let fixedPath = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

    /// The app variables brew needs (home, user, temp folder, locale, the ssh agent for git taps).
    static let baseNames: Set<String> = [
        "HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "SSH_AUTH_SOCK", "__CF_USER_TEXT_ENCODING",
    ]

    static func environment(from base: [String: String]) -> [String: String] {
        var result = base.filter { baseNames.contains($0.key) || isPassedThrough($0.key) }
        result["PATH"] = fixedPath
        return result
    }

    static let loginShellTimeout: TimeInterval = 10

    /// brew's own list: the lowercase proxy names curl and git read, the
    /// uppercase ones brew forwards, and every HOMEBREW_* setting.
    static let passedThroughNames: Set<String> = [
        "http_proxy", "https_proxy", "ftp_proxy", "no_proxy", "all_proxy",
        "HTTPS_PROXY", "FTP_PROXY", "ALL_PROXY",
    ]

    static func isPassedThrough(_ name: String) -> Bool {
        passedThroughNames.contains(name) || name.hasPrefix("HOMEBREW_")
    }

    static func passthrough(_ environment: [String: String]) -> [String: String] {
        environment.filter { isPassedThrough($0.key) }
    }

    /// Printed immediately before the dump so the startup files' own output
    /// can be told from it. Startup writes no trailing NUL, so without this the
    /// greeting and the first entry arrive as one NUL-terminated run and that
    /// entry is lost, and the first entry can be the proxy or mirror setting.
    static let dumpMarker = "__VORSSAINT_ENV_DUMP__"

    /// Set for both runs so a startup file can tell it is only being read for
    /// its exports and skip slow or interactive work, the way editors that read
    /// the shell environment mark their run: `[[ -n $VORSSAINT_RESOLVING_ENVIRONMENT ]]`.
    /// The run is a child of this app, so a protected folder a startup file
    /// touches asks for access in Vorssaint's name.
    static let resolvingVariable = "VORSSAINT_RESOLVING_ENVIRONMENT"

    /// A login shell reads `~/.zprofile`; an interactive one also reads
    /// `~/.zshrc`, which is where a proxy line is just as likely to live, so a
    /// Terminal window's environment needs both. `env -0` ends each entry with
    /// NUL so a value may contain anything, newlines included.
    static func loginShellCommand(shellPath: String, interactive: Bool = true) -> HomebrewCommand {
        HomebrewCommand(executable: shellPath,
                        arguments: (interactive ? ["-l", "-i"] : ["-l"])
                            + ["-c", "printf %s \(dumpMarker); /usr/bin/env -0"])
    }

    static func loginShellEnvironment(base: [String: String]) -> [String: String] {
        base.merging([resolvingVariable: "1"]) { _, resolving in resolving }
    }

    /// The login shell's exports that brew keeps.
    static func exportsFromLoginShell(shellPath: String,
                                      timeout: TimeInterval = loginShellTimeout,
                                      baseEnvironment: [String: String] = ProcessInfo.processInfo.environment)
        -> [String: String] {
        passthrough(loginShellExports(shellPath: shellPath, timeout: timeout, baseEnvironment: baseEnvironment))
    }

    /// Every export a Terminal window's shell has. A `.zshrc` that takes the
    /// shell over, a multiplexer autostart that fails without a terminal and
    /// exits or an `exec` into another shell, ends the interactive run before
    /// the marker. The plain login run still finds the `~/.zprofile` exports
    /// then, so it is tried whenever the interactive one gives no dump. Both
    /// run in a session of their own, so an app started from a terminal gets
    /// the same result as one started from Finder instead of a shell stopped
    /// for trying to take that terminal over.
    static func loginShellExports(shellPath: String,
                                  timeout: TimeInterval = loginShellTimeout,
                                  baseEnvironment: [String: String] = ProcessInfo.processInfo.environment)
        -> [String: String] {
        guard !shellPath.isEmpty else { return [:] }
        let environment = loginShellEnvironment(base: baseEnvironment)
        for interactive in [true, false] {
            let command = loginShellCommand(shellPath: shellPath, interactive: interactive)
            let result = BoundedProcessRunner.runInNewSession(command.executable, command.arguments,
                                                              timeout: timeout, maxOutputBytes: 1024 * 1024,
                                                              environment: environment)
            guard result.status == 0, !result.timedOut,
                  result.output.range(of: Data(dumpMarker.utf8)) != nil else { continue }
            return parse(nullSeparated: result.output)
        }
        return [:]
    }

    /// Everything up to and including the marker is whatever the startup files
    /// wrote: a greeting, a warning about a tool that is gone, or a shell's own
    /// "no job control" line, since stdout and stderr arrive on the one pipe.
    /// The last occurrence is the real one: an earlier one can only be startup
    /// echoing it, which belongs to the part being dropped. An entry whose name
    /// is not an identifier is still dropped, which is what is left of a
    /// greeting from a shell that never reached the marker at all.
    static func parse(nullSeparated data: Data) -> [String: String] {
        var environment: [String: String] = [:]
        var dump = data[...]
        if let marker = data.range(of: Data(dumpMarker.utf8), options: .backwards) {
            dump = data[marker.upperBound...]
        }
        for entry in dump.split(separator: 0) {
            guard let separator = entry.firstIndex(of: UInt8(ascii: "=")) else { continue }
            let name = String(decoding: entry[entry.startIndex..<separator], as: UTF8.self)
            guard name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { continue }
            environment[name] = String(decoding: entry[entry.index(after: separator)...], as: UTF8.self)
        }
        return environment
    }
}
