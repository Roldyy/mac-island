import FanShared
import Foundation

// Root fan helper, registered by the app with SMAppService.daemon(plistName:) and run by launchd
// (MachServices + KeepAlive {SuccessfulExit = false}). It is the only process that writes the SMC.
// Never run it by hand during development.
//
// Exit codes are read by launchd: 0 means "do not restart" (clean stop, e.g. after SIGTERM, with
// automatic restored). Anything else, or death by a signal, makes launchd relaunch the helper
// within ThrottleInterval (10 s), and the new instance's startup recovery restores automatic.
// So never exit 0 on a path that may leave a fan manual.

if CommandLine.arguments.contains("--self-test-read-only") {
    exit(HelperSelfTestCommand.run())
}

guard getuid() == 0 else {
    FileHandle.standardError.write(Data("fanhelper: must run as root under launchd\n".utf8))
    exit(77)   // EX_NOPERM
}

let daemon: HelperDaemon
do {
    daemon = try HelperDaemon(reader: AppleSMCReadOnlyClient(), writer: AppleSMCWriter())
} catch {
    FileHandle.standardError.write(Data("fanhelper: SMC unavailable: \(error)\n".utf8))
    exit(1)
}
daemon.start()
dispatchMain()
