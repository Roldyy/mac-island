import FanShared
import Foundation

// Root fan helper. Started on demand by launchd through its MachServices entry, registered by the
// app with SMAppService.daemon(plistName:). It is the only process that writes the SMC.
// Never run it by hand during development.

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
