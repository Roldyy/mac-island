import Foundation
import SettingsKit

// Shows what the first-launch import of a Vorssaint install would do.
// Names only, never values. Writes to a throwaway directory and deletes it.
let usage = "usage: mac-island-migrate --dry-run"
guard CommandLine.arguments.contains("--dry-run") else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}

let sourceID = "com.vorssaint.utils"
let home = FileManager.default.homeDirectoryForCurrentUser
let sourceSupport = home.appendingPathComponent("Library/Application Support/\(sourceID)")
let domain = UserDefaults.standard.persistentDomain(forName: sourceID) ?? [:]

let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mis-dryrun-\(UUID().uuidString)")
let suite = "mis-dryrun-\(UUID().uuidString)"
let dest = UserDefaults(suiteName: suite)!
defer {
    dest.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: tmp)
}

let report = try VorssaintMigrator(
    sourceDomain: domain, sourceSupportDir: sourceSupport,
    destDefaults: dest, destSupportDir: tmp
).run()

func list(_ title: String, _ items: [String]) {
    print("\(title) (\(items.count))")
    for item in items { print("  \(item)") }
}
print("source keys: \(domain.count)")
if report.nothingToMigrate { print("nothing to migrate"); exit(0) }
list("carried", report.migratedKeys)
list("skipped on purpose", report.skippedKeys)
list("unknown, not carried", report.unknownKeys)
list("data files", report.copiedFiles.filter { !$0.contains("/") })
print("clipboard images: \(report.copiedFiles.filter { $0.hasPrefix("ClipboardImages/") }.count)")
