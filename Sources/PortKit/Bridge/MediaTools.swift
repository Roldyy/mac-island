// SPDX-License-Identifier: GPL-3.0-or-later
// Lane W4D (media tools and wallpaper). The lane owns this file.

import AppKit
import Darwin
import SwiftUI

// MARK: - Lane

/// Binds the two ported features of lane W4-D: `mediaTools` (video compression, GIF, image and PDF conversion, text
/// from an image: Settings page "media") and `wallpaper` (the gallery and the "all Spaces" write: page "wallpaper").
///
/// Neither feature has a background activity. Both are idle until the user clicks inside their page, so a start does
/// almost nothing and nothing here ever prompts (no permission, no consent, no Apple Events):
/// - `mediaTools` start = remove the staging folders a run that died left behind (`MediaStaging.sweepLeftovers`) and
///   watch for the quit. Stop (switch off, kill switch, safe mode, quarantine, quit) = cancel the running job (the
///   external converter is killed, never left running) and remove every staging folder this process made.
/// - `wallpaper` start = the ported service re-reads its preferences; stop = the same call, which now reads the
///   registry's verdict (off) and drops the live catalog, cancels a pending apply and releases the folder access.
///   The restore point and the Index.plist copy are KEPT (patch 1053), so a switch-off or the kill switch never
///   destroys the way back. The desktop only ever changes on a click on a picture (or on "Rétablir", offered while
///   the feature is on).
///
/// External programs, every one an absolute path run with a fixed argument array (never a shell string):
/// `/usr/bin/avconvert` (video compression by resolution) and `/usr/bin/killall WallpaperAgent` (after an
/// all-Spaces write or a restore). Everything else (GIF, images, PDF, text, thumbnails) is in-process (ImageIO,
/// AVFoundation, PDFKit, Vision): there is no ffmpeg, sips or qlmanage anywhere.
///
/// Network: none. The wallpaper's "downloading" state is the materialisation of an iCloud Drive placeholder the user
/// picked (`startDownloadingUbiquitousItem`), not a URL fetch; nothing in the lane touches `URLSession`.
enum MediaToolsLane {
    /// What the lane does to the upstream services. The registry tests swap it for a fake.
    struct Runtime {
        var startMedia: @MainActor () -> Void
        var stopMedia: @MainActor () -> Void
        var startWallpaper: @MainActor () -> Void
        var stopWallpaper: @MainActor () -> Void

        static let live = Runtime(
            startMedia: { MediaToolsLifecycle.start() },
            stopMedia: { MediaToolsLifecycle.stop() },
            startWallpaper: { WallpaperLifecycle.start() },
            stopWallpaper: { WallpaperLifecycle.stop() })
    }

    /// Upstream feature id -> the Settings page that carries its body (`SettingsPageCatalog` ids; rows 54 and 11 of
    /// the reference list).
    static let pageIDs: [String: String] = ["mediaTools": "media", "wallpaper": "wallpaper"]

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        binding.bind("mediaTools",
                     page: PortFeaturePage(pageID: "media") { AnyView(MediaToolsPage()) },
                     start: { runtime.startMedia() },
                     stop: { runtime.stopMedia() })
        binding.bind("wallpaper",
                     page: PortFeaturePage(pageID: "wallpaper") { AnyView(WallpaperSettingsPage()) },
                     start: { runtime.startWallpaper() },
                     stop: { runtime.stopWallpaper() })
    }
}

// MARK: - Lifecycles

/// Start and stop of `mediaTools`. Services are only touched once a start reached them: a Mac where the feature stays
/// off builds nothing and cancels nothing.
@MainActor
enum MediaToolsLifecycle {
    /// True once a start reached the feature (tests reset it).
    static var started = false
    private static var quitToken: NSObjectProtocol?

    /// Cancels the running job and kills its external process. Swapped in tests.
    static var cancelJobs: @MainActor () -> Void = { MediaService.shared.cancel(immediately: true) }

    static func start(defaults: UserDefaults = MediaStaging.currentDefaults,
                      fileSystem: MediaFileSystem = LiveMediaFileSystem()) {
        started = true
        MediaStaging.sweepLeftovers(defaults: defaults, fileSystem: fileSystem)
        installQuitHook()
    }

    static func stop(defaults: UserDefaults = MediaStaging.currentDefaults,
                     fileSystem: MediaFileSystem = LiveMediaFileSystem()) {
        removeQuitHook()
        if started { cancelJobs() }
        MediaStaging.cleanupAll(defaults: defaults, fileSystem: fileSystem)
    }

    /// The quit: the same as a stop, minus removing the hook (the process is ending).
    static func quit(defaults: UserDefaults = MediaStaging.currentDefaults,
                     fileSystem: MediaFileSystem = LiveMediaFileSystem()) {
        if started { cancelJobs() }
        MediaStaging.cleanupAll(defaults: defaults, fileSystem: fileSystem)
    }

    private static func installQuitHook() {
        guard quitToken == nil else { return }
        quitToken = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MediaToolsLifecycle.quit() }
        }
    }

    private static func removeQuitHook() {
        if let quitToken { NotificationCenter.default.removeObserver(quitToken) }
        quitToken = nil
    }
}

/// Start and stop of `wallpaper`. Never applies anything by itself.
@MainActor
enum WallpaperLifecycle {
    private static var started = false

    static func start() {
        started = true
        WallpaperService.shared.syncWithPreferences()
    }

    /// The registry has already answered "off" for `isAvailable` when this runs, so the service drops its live
    /// state (catalog, scoped folder access, pending apply). A Mac that never started it builds no service.
    static func stop() {
        guard started else { return }
        WallpaperService.shared.syncWithPreferences()
    }
}

// MARK: - Texts

/// The French strings of this lane. The ported language tables are not part of the write surface, so they live here.
enum MediaToolsText {
    static let avconvertMissing =
        "Indisponible : l’outil de conversion vidéo du système (avconvert) est introuvable sur ce Mac. "
        + "La compression vidéo par résolution ne peut pas démarrer ; le mode « Poids », les GIF, les images et le texte fonctionnent."

    static func avconvertFailed(_ log: String) -> String {
        let trimmed = log.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "La conversion vidéo a échoué (avconvert n’a donné aucun détail)." }
        return "La conversion vidéo a échoué : \(String(trimmed.suffix(300)))"
    }

    static func timedOut(minutes: Int) -> String {
        "La conversion a été arrêtée : elle dépassait la durée maximale (\(minutes) min). Le fichier d’origine n’a pas été modifié."
    }

    static let invalidPath = "Ce chemin de fichier ne peut pas être utilisé pour la conversion."
    static let invalidNumber = "Les valeurs de début ou de durée ne sont pas valides."
    static let unknownPreset = "Réglage de compression inconnu : la conversion n’a pas été lancée."
    static let sameFile = "Le fichier de sortie est le fichier d’origine : rien n’a été converti."

    static let restoreWallpaper = "Rétablir le fond"
    static let restoreWallpaperHelp =
        "Remet le fond d’écran que vous aviez avant le premier changement fait depuis Mac Island."
    static let restoreWallpaperFailed = "Impossible de rétablir le fond d’écran précédent."
    static let wallpaperNote =
        "Le fond d’écran ne change que lorsque vous cliquez sur une image. Mac Island garde l’état précédent pour pouvoir le "
        + "rétablir. Après une migration depuis une autre app, ajoutez à nouveau vos dossiers : l’accès autorisé n’est pas repris."
}

// MARK: - External programs

/// Every program the media and wallpaper code may run. A new entry here is a reviewed decision: the source gate in
/// `MediaToolsSourceTests` fails when a lane file names an executable that is not in this list.
enum MediaExternalTool: CaseIterable {
    /// Video compression by resolution (`Preset…`). The only video encoder run as a program.
    case avconvert
    /// Restarts `WallpaperAgent` after the wallpaper store was rewritten (`killall WallpaperAgent`, via `Shell.run`).
    case killall

    var path: String {
        switch self {
        case .avconvert: "/usr/bin/avconvert"
        case .killall: "/usr/bin/killall"
        }
    }

    /// The French reason when the program is not on this Mac.
    var unavailableReason: String {
        switch self {
        case .avconvert: MediaToolsText.avconvertMissing
        case .killall:
            "Indisponible : l’outil système killall est introuvable ; le fond d’écran sera pris en compte au prochain démarrage de la session."
        }
    }
}

enum MediaToolAvailability {
    static func isAvailable(_ tool: MediaExternalTool, fileSystem: MediaFileSystem = LiveMediaFileSystem()) -> Bool {
        fileSystem.isExecutableFile(atPath: tool.path)
    }

    /// nil when the tool is there, the French reason when it is not.
    static func unavailableReason(_ tool: MediaExternalTool,
                                  fileSystem: MediaFileSystem = LiveMediaFileSystem()) -> String? {
        isAvailable(tool, fileSystem: fileSystem) ? nil : tool.unavailableReason
    }
}

// MARK: - Commands

/// A program and its argument array. There is no string that a shell could re-split: the paths of the user's files
/// are single elements, whatever they contain.
struct MediaToolCommand: Equatable {
    let tool: MediaExternalTool
    let arguments: [String]
    var executablePath: String { tool.path }
}

enum MediaToolsError: Error, Equatable {
    case invalidPath
    case invalidNumber
    case unknownPreset(String)
    case sameFile

    var message: String {
        switch self {
        case .invalidPath: MediaToolsText.invalidPath
        case .invalidNumber: MediaToolsText.invalidNumber
        case .unknownPreset: MediaToolsText.unknownPreset
        case .sameFile: MediaToolsText.sameFile
        }
    }
}

enum MediaAvconvertCommand {
    /// The presets `MediaService.avconvertPreset` can pick. Anything else is refused.
    static let allowedPresets: Set<String> = [
        "PresetLowQuality", "PresetMediumQuality", "PresetHighestQuality",
        "PresetHEVCHighestQuality", "PresetHEVC1920x1080", "PresetHEVC3840x2160",
        "Preset640x480", "Preset960x540", "Preset1280x720", "Preset1920x1080",
    ]

    /// `source` and `output` must be absolute file URLs, so a name that starts with a dash can never be read as an
    /// option. The output is the staged file (a fresh one in a private folder), never a user file.
    static func make(source: URL, output: URL, preset: String, start: Double, duration: Double,
                     multiPass: Bool) throws -> MediaToolCommand {
        let sourcePath = try absolutePath(source)
        let outputPath = try absolutePath(output)
        guard sourcePath != outputPath else { throw MediaToolsError.sameFile }
        guard allowedPresets.contains(preset) else { throw MediaToolsError.unknownPreset(preset) }
        guard start.isFinite, duration.isFinite, start >= 0, duration > 0 else { throw MediaToolsError.invalidNumber }
        var arguments = [
            "--source", sourcePath,
            "--preset", preset,
            "--output", outputPath,
            "--replace",
            "--progress",
            // Not the reader's region: a tool that reads a decimal point breaks on a comma.
            "--start", seconds(start),
            "--duration", seconds(duration),
        ]
        if multiPass { arguments.append("--multiPass") }
        return MediaToolCommand(tool: .avconvert, arguments: arguments)
    }

    static func seconds(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// A file URL whose path is absolute, has no NUL byte and fits `PATH_MAX`. Spaces, quotes, newlines and a
    /// leading dash in a NAME are fine: the path starts with "/" and travels as one array element.
    static func absolutePath(_ url: URL) throws -> String {
        guard url.isFileURL else { throw MediaToolsError.invalidPath }
        let path = url.path
        guard path.hasPrefix("/"), path.utf8.count < Int(PATH_MAX), !path.utf8.contains(0) else {
            throw MediaToolsError.invalidPath
        }
        return path
    }
}

// MARK: - Running a process

/// How a run ended.
enum MediaRunOutcome: Equatable {
    case finished(status: Int32, log: String)
    case cancelled
    case timedOut
    /// The program is not on this Mac: the French reason. Nothing was launched.
    case toolUnavailable(String)
}

struct MediaRunLimits: Equatable {
    /// Wall-clock budget. When it is spent the program is stopped.
    var timeout: TimeInterval
    /// How long a program gets after `terminate()` before it is killed.
    var graceSeconds: TimeInterval = 2
    var pollInterval: TimeInterval = 0.08
}

/// The part of a running program the supervisor needs. Live: a `Process`. Tests: a script.
protocol MediaProcessHandle: AnyObject {
    var isRunning: Bool { get }
    var terminationStatus: Int32 { get }
    func terminate()
    func forceKill()
}

struct MediaClock {
    var now: () -> TimeInterval
    var sleep: (TimeInterval) -> Void

    static let live = MediaClock(now: { ProcessInfo.processInfo.systemUptime },
                                 sleep: { Thread.sleep(forTimeInterval: $0) })
}

enum MediaSuperviseResult: Equatable {
    case exited(Int32)
    case cancelled
    case timedOut
}

/// Waits for a program: cancellation and the time budget both stop it (SIGTERM, then SIGKILL after the grace).
enum MediaProcessSupervisor {
    static func supervise(_ handle: MediaProcessHandle, limits: MediaRunLimits,
                          isCancelled: () -> Bool,
                          clock: MediaClock = .live,
                          onTick: (TimeInterval) -> Void = { _ in }) -> MediaSuperviseResult {
        let started = clock.now()
        while handle.isRunning {
            if isCancelled() {
                stop(handle, limits: limits, clock: clock)
                return .cancelled
            }
            let elapsed = clock.now() - started
            if elapsed >= limits.timeout {
                stop(handle, limits: limits, clock: clock)
                return .timedOut
            }
            onTick(elapsed)
            clock.sleep(limits.pollInterval)
        }
        if isCancelled() { return .cancelled }
        return .exited(handle.terminationStatus)
    }

    private static func stop(_ handle: MediaProcessHandle, limits: MediaRunLimits, clock: MediaClock) {
        handle.terminate()
        let deadline = clock.now() + limits.graceSeconds
        while handle.isRunning, clock.now() < deadline { clock.sleep(limits.pollInterval) }
        if handle.isRunning { handle.forceKill() }
    }
}

/// Runs a `MediaToolCommand`. Live: `LiveMediaProcessRunner`. Tests: a fake that captures the argument arrays.
protocol MediaProcessRunning {
    /// `launch` receives the configured `Process` and starts it (the service registers it for its own cancel there);
    /// a fake never calls it. `onTick` gets the elapsed seconds while the program runs.
    func run(_ command: MediaToolCommand, limits: MediaRunLimits, isCancelled: @escaping () -> Bool,
             launch: (Process) throws -> Void, onTick: (TimeInterval) -> Void) throws -> MediaRunOutcome
}

/// Where the media service gets its runner, and how long a video may take.
enum MediaToolsRuntime {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var current: MediaProcessRunning = LiveMediaProcessRunner()

    static var runner: MediaProcessRunning {
        get { lock.lock(); defer { lock.unlock() }; return current }
        set { lock.lock(); current = newValue; lock.unlock() }
    }

    /// Eight times the clip plus two minutes, at least five minutes, at most six hours.
    static func limits(forVideoSeconds seconds: Double) -> MediaRunLimits {
        let clip = seconds.isFinite ? max(0, seconds) : 0
        return MediaRunLimits(timeout: min(21_600, max(300, clip * 8 + 120)))
    }
}

struct LiveMediaProcessRunner: MediaProcessRunning {
    /// The CPU priority given to every converter: `nice 10`, so a long compression never competes with the user.
    static let niceValue: Int32 = 10
    var fileSystem: MediaFileSystem = LiveMediaFileSystem()
    var clock: MediaClock = .live

    func run(_ command: MediaToolCommand, limits: MediaRunLimits, isCancelled: @escaping () -> Bool,
             launch: (Process) throws -> Void, onTick: (TimeInterval) -> Void) throws -> MediaRunOutcome {
        guard fileSystem.isExecutableFile(atPath: command.executablePath) else {
            return .toolUnavailable(command.tool.unavailableReason)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executablePath)
        process.arguments = command.arguments
        process.qualityOfService = .utility
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let log = BoundedLog(limit: 16_000)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { log.append(data) }
        }
        let handle = LiveMediaProcessHandle(process)
        defer {
            pipe.fileHandleForReading.readabilityHandler = nil
            handle.terminate()
            try? pipe.fileHandleForReading.close()
        }
        try launch(process)
        _ = setpriority(PRIO_PROCESS, id_t(process.processIdentifier), Self.niceValue)
        switch MediaProcessSupervisor.supervise(handle, limits: limits, isCancelled: isCancelled, clock: clock,
                                                onTick: onTick) {
        case .exited(let status): return .finished(status: status, log: log.text)
        case .cancelled: return .cancelled
        case .timedOut: return .timedOut
        }
    }
}

final class LiveMediaProcessHandle: MediaProcessHandle {
    private let process: Process
    init(_ process: Process) { self.process = process }
    var isRunning: Bool { process.isRunning }
    var terminationStatus: Int32 { process.terminationStatus }
    func terminate() { if process.isRunning { process.terminate() } }
    func forceKill() { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
}

/// The tail of a program's output, thread-safe and capped.
final class BoundedLog: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let limit: Int
    init(limit: Int) { self.limit = limit }

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        if data.count > limit { data = data.suffix(limit) }
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - File system seam

/// The file operations of this lane, behind a seam so tests run on a dictionary and never on the real disk.
protocol MediaFileSystem {
    func fileExists(atPath path: String) -> Bool
    func isExecutableFile(atPath path: String) -> Bool
    func isDirectory(atPath path: String) -> Bool
    func isSymbolicLink(atPath path: String) -> Bool
    func contentsOfDirectory(atPath path: String) -> [String]?
    /// A new folder readable by the owner only (0700). Throws when it exists.
    func createPrivateDirectory(atPath path: String) throws
    func setPrivatePermissions(atPath path: String) throws
    func permissions(atPath path: String) -> Int?
    func readData(atPath path: String) -> Data?
    func writeAtomically(_ data: Data, toPath path: String) throws
    func removeItem(atPath path: String) throws
}

struct LiveMediaFileSystem: MediaFileSystem {
    var fileManager: FileManager = .default

    func fileExists(atPath path: String) -> Bool {
        // lstat: a dangling link still holds the name, so it counts as taken.
        var info = stat()
        return lstat(path, &info) == 0
    }

    func isExecutableFile(atPath path: String) -> Bool { fileManager.isExecutableFile(atPath: path) }

    func isDirectory(atPath path: String) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    func isSymbolicLink(atPath path: String) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: path)) != nil
    }

    func contentsOfDirectory(atPath path: String) -> [String]? { try? fileManager.contentsOfDirectory(atPath: path) }

    func createPrivateDirectory(atPath path: String) throws {
        try fileManager.createDirectory(atPath: path, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
    }

    func setPrivatePermissions(atPath path: String) throws {
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
    }

    func permissions(atPath path: String) -> Int? {
        (try? fileManager.attributesOfItem(atPath: path))?[.posixPermissions] as? Int
    }

    func readData(atPath path: String) -> Data? { fileManager.contents(atPath: path) }

    func writeAtomically(_ data: Data, toPath path: String) throws {
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    func removeItem(atPath path: String) throws { try fileManager.removeItem(atPath: path) }
}

// MARK: - Staging folders

/// The private folders a conversion writes into before the result is moved next to the source in one step.
///
/// The folder itself comes from the system (`itemReplacementDirectory`, on the volume of the output so the final move
/// is one rename); this registry makes it owner-only (0700), remembers it, and removes it again: after the job
/// (`discard`), at the quit and on a stop (`cleanupAll`), and at the next start when the run died before cleaning
/// (`sweepLeftovers`, from a journal in the defaults). Removal is conservative: the user's file is never inside, and a
/// folder this process did not register only ever loses a file named `Output…`.
enum MediaStaging {
    static let journalKey = "macisland.media.stagingDirectories"
    private static let lock = NSLock()
    private nonisolated(unsafe) static var live: Set<String> = []

    /// Where the journal is kept when a caller does not say: the host's defaults. Tests point it at a temporary suite.
    nonisolated(unsafe) static var journalDefaults: UserDefaults?
    static var currentDefaults: UserDefaults { journalDefaults ?? PortHost.defaults }

    /// Makes the folder owner-only and starts tracking it.
    static func register(_ directory: URL, defaults: UserDefaults = MediaStaging.currentDefaults,
                         fileSystem: MediaFileSystem = LiveMediaFileSystem()) {
        let path = directory.path
        try? fileSystem.setPrivatePermissions(atPath: path)
        lock.lock()
        live.insert(path)
        lock.unlock()
        updateJournal(defaults) { $0.insert(path) }
    }

    static func owns(_ directory: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return live.contains(directory.path)
    }

    /// The live folders, sorted (tests).
    static var liveDirectories: [String] {
        lock.lock()
        defer { lock.unlock() }
        return live.sorted()
    }

    /// Removes what a job staged. A registered folder goes whole (this process made it); for any other folder only
    /// the staged file is removed and only when it is named `Output…`, so a source file next to it is never touched.
    static func discard(_ staged: URL, defaults: UserDefaults = MediaStaging.currentDefaults,
                        fileSystem: MediaFileSystem = LiveMediaFileSystem()) {
        let directory = staged.deletingLastPathComponent()
        if owns(directory) {
            try? fileSystem.removeItem(atPath: directory.path)
            forget(directory.path, defaults: defaults)
        } else if staged.lastPathComponent.hasPrefix("Output") {
            try? fileSystem.removeItem(atPath: staged.path)
        }
    }

    /// Every folder this process made. The quit and every stop.
    static func cleanupAll(defaults: UserDefaults = MediaStaging.currentDefaults,
                           fileSystem: MediaFileSystem = LiveMediaFileSystem()) {
        lock.lock()
        let paths = live
        lock.unlock()
        for path in paths {
            try? fileSystem.removeItem(atPath: path)
            forget(path, defaults: defaults)
        }
    }

    /// Folders a dead run left in the journal. A folder is removed only when it is a real directory (not a link),
    /// is not one of ours right now, and holds nothing but files named `Output…`. Entries that are gone are dropped;
    /// a folder that holds anything else stays (and stays listed). Returns the removed paths.
    @discardableResult
    static func sweepLeftovers(defaults: UserDefaults = MediaStaging.currentDefaults,
                               fileSystem: MediaFileSystem = LiveMediaFileSystem()) -> [String] {
        let journaled = journal(defaults)
        var removed: [String] = []
        for path in journaled {
            lock.lock()
            let isLive = live.contains(path)
            lock.unlock()
            if isLive { continue }
            guard fileSystem.fileExists(atPath: path) else {
                forget(path, defaults: defaults)
                continue
            }
            guard fileSystem.isDirectory(atPath: path), !fileSystem.isSymbolicLink(atPath: path),
                  let entries = fileSystem.contentsOfDirectory(atPath: path),
                  entries.allSatisfy({ $0.hasPrefix("Output") }) else { continue }
            if (try? fileSystem.removeItem(atPath: path)) != nil {
                removed.append(path)
                forget(path, defaults: defaults)
            }
        }
        return removed
    }

    static func journal(_ defaults: UserDefaults) -> [String] {
        (defaults.array(forKey: journalKey) as? [String]) ?? []
    }

    private static func forget(_ path: String, defaults: UserDefaults) {
        lock.lock()
        live.remove(path)
        lock.unlock()
        updateJournal(defaults) { $0.remove(path) }
    }

    private static func updateJournal(_ defaults: UserDefaults, _ change: (inout Set<String>) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var set = Set((defaults.array(forKey: journalKey) as? [String]) ?? [])
        let before = set
        change(&set)
        guard set != before else { return }
        if set.isEmpty { defaults.removeObject(forKey: journalKey) } else { defaults.set(set.sorted(), forKey: journalKey) }
    }
}

// MARK: - Output names

/// Mac Island never overwrites a file: a taken name gets " 2", " 3"... like the ported default names.
enum MediaOutputNaming {
    static let liveExists: (String) -> Bool = { LiveMediaFileSystem().fileExists(atPath: $0) }

    /// `candidate` when nothing is there (and nobody reserved it), else the first free "name N.ext" beside it.
    static func availableURL(_ candidate: URL, reserved: Set<String> = [],
                             exists: (String) -> Bool = liveExists) -> URL {
        func taken(_ url: URL) -> Bool { reserved.contains(url.path) || exists(url.path) }
        guard taken(candidate) else { return candidate }
        let directory = candidate.deletingLastPathComponent()
        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var index = 2
        while true {
            let suffix = " \(index)"
            let name = MediaSupport.sanitizedFileBaseName(base, fileExtension: ext,
                                                          uniquenessSuffixByteReservation: suffix.utf8.count)
            var url = directory.appendingPathComponent("\(name)\(suffix)")
            if !ext.isEmpty { url.appendPathExtension(ext) }
            if !taken(url) { return url }
            index += 1
        }
    }
}

// MARK: - Wallpaper restore

/// Where the desktop was before Mac Island changed it: one image per screen, as file URLs.
struct WallpaperRestorePoint: Codable, Equatable {
    var images: [String: String]
}

/// The desktop as the restore sees it. Live: `NSWorkspace` and `NSScreen`, main thread only.
protocol WallpaperDesktop {
    func screenIDs() -> [String]
    func currentImage(forScreen id: String) -> URL?
    func setImage(_ url: URL, forScreen id: String) throws
}

struct WallpaperRestoreOutcome: Equatable {
    var screensRestored = 0
    var screensFailed = 0
    var index: Index = .none
    var agentRestarted = true

    enum Index: Equatable { case none, restored, failed }

    /// Nothing failed (including "nothing to do").
    var succeeded: Bool { screensFailed == 0 && index != .failed }
    var didRestoreAnything: Bool { screensRestored > 0 || index == .restored }
}

/// "Rétablir le fond d’écran précédent". Two independent things can be restored, both only on a click:
/// - the image of each screen, recorded before the FIRST change made from Mac Island (a one-shot point: no later
///   apply overwrites it, like the Index.plist copy);
/// - the Sonoma wallpaper store (`Index.plist`), from the copy `WallpaperStore.ensureBackup` made before the first
///   all-Spaces write. The copy is parsed before anything is written, the write is atomic, and `WallpaperAgent` is
///   restarted afterwards. Both records are removed once they are applied; a failure keeps them for another try.
struct WallpaperRestorer {
    static let pointKey = "macisland.wallpaper.restorePoint"

    var defaults: UserDefaults
    var fileSystem: MediaFileSystem
    var desktop: WallpaperDesktop
    var indexPath: String
    var backupPath: String
    /// Restarts the wallpaper agent. True when it was restarted or was not running.
    var restartAgent: () -> Bool

    var storedPoint: WallpaperRestorePoint? {
        guard let data = defaults.data(forKey: Self.pointKey) else { return nil }
        return try? JSONDecoder().decode(WallpaperRestorePoint.self, from: data)
    }

    var hasIndexBackup: Bool { fileSystem.fileExists(atPath: backupPath) }
    var canRestore: Bool { storedPoint != nil || hasIndexBackup }

    /// Remembers the current image of every screen when nothing is remembered yet. Called before an apply.
    func captureIfNeeded() {
        guard !canRestore else { return }
        var images: [String: String] = [:]
        for id in desktop.screenIDs() {
            guard let url = desktop.currentImage(forScreen: id), url.isFileURL,
                  fileSystem.fileExists(atPath: url.path) else { continue }
            images[id] = url.absoluteString
        }
        guard !images.isEmpty, let data = try? JSONEncoder().encode(WallpaperRestorePoint(images: images)) else { return }
        defaults.set(data, forKey: Self.pointKey)
    }

    /// Main thread (NSWorkspace). Screens that are gone, and images that are gone, are skipped, not failed.
    func restoreScreens() -> (restored: Int, failed: Int) {
        guard let point = storedPoint else { return (0, 0) }
        let present = Set(desktop.screenIDs())
        var restored = 0
        var failed = 0
        for (id, string) in point.images.sorted(by: { $0.key < $1.key }) {
            guard present.contains(id), let url = URL(string: string), url.isFileURL,
                  fileSystem.fileExists(atPath: url.path) else { continue }
            do {
                try desktop.setImage(url, forScreen: id)
                restored += 1
            } catch {
                failed += 1
            }
        }
        return (restored, failed)
    }

    /// Any thread (a file write and a process). Restores `Index.plist` from the copy; nothing when there is none.
    func restoreIndex() -> (result: WallpaperRestoreOutcome.Index, agentRestarted: Bool) {
        guard hasIndexBackup else { return (.none, true) }
        guard let data = fileSystem.readData(atPath: backupPath),
              (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) is [String: Any] else {
            return (.failed, true)
        }
        do {
            try fileSystem.writeAtomically(data, toPath: indexPath)
        } catch {
            return (.failed, true)
        }
        let restarted = restartAgent()
        try? fileSystem.removeItem(atPath: backupPath)
        return (.restored, restarted)
    }

    /// Drops the point once its screens are done. A failure anywhere keeps it.
    func finish(_ outcome: WallpaperRestoreOutcome) {
        if outcome.succeeded { defaults.removeObject(forKey: Self.pointKey) }
    }

    /// Both steps, in order, on the calling thread (tests, and callers that are already on the main thread).
    @discardableResult
    func restore() -> WallpaperRestoreOutcome {
        var outcome = WallpaperRestoreOutcome()
        let screens = restoreScreens()
        outcome.screensRestored = screens.restored
        outcome.screensFailed = screens.failed
        let index = restoreIndex()
        outcome.index = index.result
        outcome.agentRestarted = index.agentRestarted
        finish(outcome)
        return outcome
    }
}

enum WallpaperRestore {
    /// A restorer on the live host. Built at each call: the defaults object can change (launch, tests).
    static var live: WallpaperRestorer {
        WallpaperRestorer(
            defaults: PortHost.defaults,
            fileSystem: LiveMediaFileSystem(),
            desktop: LiveWallpaperDesktop(),
            indexPath: WallpaperStore.indexURL.path,
            backupPath: WallpaperStore.backupURL.path,
            restartAgent: {
                guard MediaToolAvailability.isAvailable(.killall) else { return false }
                // killall exits 1 when no WallpaperAgent runs: nothing to restart, the next one reads the store.
                let status = Shell.run(MediaExternalTool.killall.path, ["WallpaperAgent"]).status
                return status == 0 || status == 1
            })
    }
}

struct LiveWallpaperDesktop: WallpaperDesktop {
    private func screen(_ id: String) -> NSScreen? { NSScreen.screens.first { Self.id(of: $0) == id } }

    static func id(of screen: NSScreen) -> String? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
    }

    func screenIDs() -> [String] { NSScreen.screens.compactMap(Self.id(of:)) }

    func currentImage(forScreen id: String) -> URL? {
        screen(id).flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
    }

    func setImage(_ url: URL, forScreen id: String) throws {
        guard let screen = screen(id) else { return }
        try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
    }
}

// MARK: - Pages

/// Page "media" (row 54): the ported workspace, under a notice when the video converter is not on this Mac.
private struct MediaToolsPage: View {
    @State private var converterMissing = !MediaToolAvailability.isAvailable(.avconvert)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if converterMissing {
                Label(MediaToolsText.avconvertMissing, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            MediaSettings()
        }
        .onAppear { converterMissing = !MediaToolAvailability.isAvailable(.avconvert) }
    }
}

/// Page "wallpaper" (row 11): the ported gallery (it carries the "all Spaces" switch, the folder pickers, the link to
/// the system settings and, once something was changed, "Rétablir"), with a note on what is and is not automatic.
private struct WallpaperSettingsPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WallpaperSection(collapsible: false)
            Text(MediaToolsText.wallpaperNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
