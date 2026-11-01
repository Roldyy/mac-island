// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Darwin
import Foundation

/// Restores the HID values if the app disappears before normal termination.
/// The child waits for EOF on a pipe owned by the app, which the kernel closes
/// after both ordinary exit and SIGKILL.
enum MouseAccelerationGuard {
    static let cleanupArgument = "--mouse-acceleration-cleanup"
    private static let cleanupTimeout: TimeInterval = 5

    /// The running guard child, or a stand-in: `stop()` hands the restore over and reports whether it succeeded.
    final class Handle {
        private let onStop: () -> Bool

        /// A handle with its own stop. Tests use it so no process is spawned.
        init(onStop: @escaping () -> Bool) {
            self.onStop = onStop
        }

        fileprivate static func launch() -> Handle? {
            guard let executable = Bundle.main.executableURL?.path else { return nil }

            let process = Process()
            let inputPipe = Pipe()
            let finished = DispatchSemaphore(value: 0)
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [
                "-c",
                "IFS= read -r _; exec \"$1\" \"$2\"",
                "sh", executable, cleanupArgument,
            ]
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

            let input = inputPipe.fileHandleForWriting
            return Handle {
                try? input.close()
                var didFinish = finished.wait(
                    timeout: .now() + MouseAccelerationGuard.cleanupTimeout + 1
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

        func stop() -> Bool {
            onStop()
        }
    }

    /// How the guard child is launched. Swapped by tests only.
    nonisolated(unsafe) static var launcher: () -> Handle? = { Handle.launch() }

    static func start() -> Handle? {
        launcher()
    }

    static func runIfRequestedAndExit() {
        guard CommandLine.arguments.contains(cleanupArgument) else { return }
        exit(MouseAccelerationRecovery.restorePending() ? EXIT_SUCCESS : EXIT_FAILURE)
    }
}
