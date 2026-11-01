// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Darwin
import Foundation

/// Keeps the selected key recoverable if the app is killed before normal
/// termination can remove its HID mapping. A tiny shell waits on a pipe owned
/// by the app, then replaces itself with this executable's cleanup mode when
/// the pipe closes. The kernel closes it on both ordinary exit and SIGKILL.
enum SuperKeyMappingGuard {
    static let cleanupArgument = "--super-key-mapping-cleanup"
    private static let commandTimeout: TimeInterval = 5

    /// Mac Island: ONE time budget for taking the mapping out when the feature stops, counted from the moment
    /// the stop was asked for (a queue backlog eats it too). The clear runs off the main thread within it; past
    /// it nothing more is waited for and the guard child, which already has the pipe closed, finishes the job.
    struct StopBudget {
        /// A registry stop (kill switch, safe mode, permission revoked): nobody waits for it.
        static let asyncTotal: TimeInterval = 3
        /// `applicationWillTerminate`: the only place the main thread may wait, and for this long at most.
        static let terminationTotal: TimeInterval = 2
        /// Test seam: the clock (system uptime).
        nonisolated(unsafe) static var uptime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

        let total: TimeInterval
        private let deadline: TimeInterval

        init(seconds: TimeInterval) {
            total = seconds
            deadline = Self.uptime() + seconds
        }

        var remaining: TimeInterval { max(0, deadline - Self.uptime()) }
        var isExhausted: Bool { remaining <= 0 }
    }

    /// Test seam: the guard child's command, so a test starts a harmless child that waits on the pipe like the
    /// real one and never re-executes the test binary.
    nonisolated(unsafe) static var launchOverride: ((SuperKeySource) -> (executable: String, arguments: [String]))?

    final class Handle {
        let source: SuperKeySource

        private let process: Process
        private let input: FileHandle
        private let finished: DispatchSemaphore

        fileprivate init?(source: SuperKeySource) {
            let command: (executable: String, arguments: [String])
            if let launchOverride = SuperKeyMappingGuard.launchOverride {
                command = launchOverride(source)
            } else {
                guard let executable = Bundle.main.executableURL?.path else { return nil }
                command = ("/bin/sh", [
                    "-c",
                    "IFS= read -r _; exec \"$1\" \"$2\" \"$3\"",
                    "sh", executable, cleanupArgument, source.rawValue,
                ])
            }

            let process = Process()
            let inputPipe = Pipe()
            let finished = DispatchSemaphore(value: 0)
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
            process.standardInput = inputPipe
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { _ in finished.signal() }

            do {
                try process.run()
            } catch {
                try? inputPipe.fileHandleForWriting.close()
                return nil
            }

            self.source = source
            self.process = process
            self.input = inputPipe.fileHandleForWriting
            self.finished = finished
        }

        /// Closing the pipe asks the guard to clean now. The app has already
        /// attempted the same clear; this bounded second pass covers a failed
        /// command without ever holding termination indefinitely.
        ///
        /// `budget` (Mac Island): the most this call may wait. The pipe is closed first either way, so the guard
        /// child starts its own cleanup at once; when the budget runs out the child is LEFT RUNNING (it is the
        /// one that gives the key back) and the answer is "not confirmed", which keeps the recovery marker.
        func stop(within budget: TimeInterval? = nil) -> Bool {
            try? input.close()
            if let budget {
                guard finished.wait(timeout: .now() + max(0, budget)) == .success else { return false }
                return process.terminationStatus == EXIT_SUCCESS
            }
            var didFinish = finished.wait(
                timeout: .now() + SuperKeyMappingGuard.commandTimeout + 1
            ) == .success
            if !didFinish {
                process.terminate()
                didFinish = finished.wait(timeout: .now() + 0.5) == .success
            }
            if !didFinish {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 0.5)
            }
            return didFinish && process.terminationStatus == EXIT_SUCCESS
        }
    }

    static func start(source: SuperKeySource) -> Handle? {
        Handle(source: source)
    }

    /// Runs before NSApplication is created when the waiting guard observes
    /// that its parent disappeared.
    static func runIfRequestedAndExit() {
        let arguments = CommandLine.arguments
        guard arguments.contains(cleanupArgument) else { return }
        guard let source = cleanupSource(in: arguments) else { exit(EXIT_FAILURE) }
        exit(clear(source: source) ? EXIT_SUCCESS : EXIT_FAILURE)
    }

    static func cleanupSource(in arguments: [String]) -> SuperKeySource? {
        guard let index = arguments.firstIndex(of: cleanupArgument),
              arguments.indices.contains(index + 1)
        else { return nil }
        return SuperKeySource(rawValue: arguments[index + 1])
    }

    /// The report is reduced to the table that remains after this feature's
    /// exact source-to-F18 entry is removed. Different external tables are
    /// refused instead of copying one keyboard's mappings onto another.
    static func mappingsAfterCleanup(_ report: String,
                                     source: SuperKeySource) -> [SuperKeyMapping]? {
        SuperKeySupport.consistentMappings(
            report,
            property: SuperKeySupport.userMappingProperty,
            ownedSource: source
        )
    }

    /// Removes this feature's own entry from the keyboard mapping table. Internal so the restore path can be
    /// run against a fake `hidutil` (`runHIDOverride`).
    static func clear(source: SuperKeySource) -> Bool {
        let report = runHID(
            ["property", "--matching", "keyboard",
             "--get", SuperKeySupport.userMappingProperty]
        )
        guard report.status == 0,
              let remaining = mappingsAfterCleanup(report.output, source: source)
        else { return false }
        if SuperKeySupport.mappingReportConfirms(report.output, expected: remaining) {
            return true
        }

        let write = runHID(
            ["property", "--matching", "keyboard",
             "--set", SuperKeySupport.mappingArgument(remaining)]
        )
        guard write.status == 0 else { return false }
        let readback = runHID(
            ["property", "--matching", "keyboard",
             "--get", SuperKeySupport.userMappingProperty]
        )
        return readback.status == 0
            && SuperKeySupport.mappingReportConfirms(readback.output, expected: remaining)
    }

    /// Replaces `hidutil` in tests, so the restore path runs without touching the real keyboard mapping.
    nonisolated(unsafe) static var runHIDOverride: (([String]) -> (status: Int32, output: String))?

    /// The one door to `hidutil`: the guard's cleanup and the service's apply, clear and readback all use it.
    /// `budget` (Mac Island): a command never runs longer than what is left of it.
    static func runHID(_ arguments: [String], budget: StopBudget? = nil) -> (status: Int32, output: String) {
        if let runHIDOverride { return runHIDOverride(arguments) }
        let result = BoundedProcessRunner.run(
            "/usr/bin/hidutil",
            arguments,
            timeout: min(commandTimeout, budget?.remaining ?? commandTimeout),
            maxOutputBytes: 4 * 1024 * 1024
        )
        return (result.status, String(decoding: result.output, as: UTF8.self))
    }
}
