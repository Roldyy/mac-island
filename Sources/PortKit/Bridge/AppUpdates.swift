// SPDX-License-Identifier: GPL-3.0-or-later
// Lane W7C (app updates and Homebrew). The lane owns this file.

import AppKit
import Combine
import Darwin
import IslandUI
import SwiftUI

// MARK: - Lane

/// Binds the two ported features of lane W7-C: `appUpdates` (which installed apps have a newer version, from
/// Homebrew, the App Store lookup and the publishers' own feeds: Settings page "appupdates") and `homebrew`
/// (outdated, upgrade, install and uninstall of formulae and casks, plus the cleanup added here: page "homebrew").
///
/// Nothing runs at rest:
/// - `appUpdates` start = `AppUpdatesService.syncWithPreferences()`, which arms the background timer only when the
///   person chose a frequency (the default is "off"). It never fetches by itself at start. Stop (switch off, kill
///   switch, safe mode, quarantine) = the same call after the binding denied the feature: the timer and the wake
///   observer go, and a scan still in flight drops its answer (the service re-reads `isAvailable`).
/// - `homebrew` has no background activity at all. Stop cancels a running brew operation and a running cleanup.
///
/// Every external program is an absolute path run with a fixed argument array, never a shell string: the brew
/// found by `BrewLocator` (`info`, `outdated`, `upgrade`, `update`, `search`, `install`, `uninstall`, `trust`,
/// `cleanup`) and `/usr/bin/mdfind` (the Spotlight application list). No `sh -c`, no login shell (patch 1550),
/// no Terminal and no Apple Events: a command the app cannot run itself (the Homebrew installer, a `sudo`
/// step) is copied for the person to paste (patch 1552).
///
/// Network, only from the page the person opened or from the schedule they switched on: `formulae.brew.sh` (the
/// popularity table), `itunes.apple.com` and `uclient-api.itunes.apple.com` (App Store versions), the online
/// catalog the service already used and the https update feeds an installed app declares itself.
enum AppUpdatesLane {
    /// What the lane does to the upstream services. The registry tests swap it for a fake.
    struct Runtime {
        var syncUpdates: @MainActor () -> Void
        var stopUpdates: @MainActor () -> Void
        var startHomebrew: @MainActor () -> Void
        var stopHomebrew: @MainActor () -> Void

        @MainActor private static var updatesTouched = false
        @MainActor private static var homebrewTouched = false

        static let live = Runtime(
            syncUpdates: { updatesTouched = true; AppUpdatesService.shared.syncWithPreferences() },
            stopUpdates: { if updatesTouched { AppUpdatesService.shared.syncWithPreferences() } },
            startHomebrew: { homebrewTouched = true },
            stopHomebrew: {
                guard homebrewTouched else { return }
                HomebrewManager.shared.cancelOperation()
                HomebrewCleanupModel.shared.cancel()
            })
    }

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        binding.bind("appUpdates",
                     page: PortFeaturePage(pageID: "appupdates") { AnyView(AppUpdatesSettings()) },
                     start: { runtime.syncUpdates() },
                     stop: { runtime.stopUpdates() })
        binding.bind("homebrew",
                     page: PortFeaturePage(pageID: "homebrew") { AnyView(HomebrewPage()) },
                     start: { runtime.startHomebrew() },
                     stop: { runtime.stopHomebrew() })
    }
}

// MARK: - Finding brew

/// Where brew is, found among the known prefixes and checked before anything runs it. The discovery answers
/// with a path the app then runs with a fixed argument array; it never reads `PATH` and never starts a shell.
enum BrewLocator {
    /// Apple silicon, then Intel.
    static let knownCandidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    /// What `stat` says about a candidate (symbolic links followed).
    struct Facts: Equatable {
        var isRegularFile: Bool
        var isExecutable: Bool
        var ownerUID: UInt32
        /// The permission bits (`st_mode & 0o7777`).
        var mode: UInt16
    }

    /// `HOMEBREW_PREFIX` first when it is a clean absolute path, then the two known prefixes.
    static func candidates(environment: [String: String]) -> [String] {
        var result: [String] = []
        if let prefix = environment["HOMEBREW_PREFIX"], isCleanAbsolute(prefix) {
            let trimmed = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
            result.append(trimmed + "/bin/brew")
        }
        for known in knownCandidates where !result.contains(known) { result.append(known) }
        return result
    }

    /// An executable regular file owned by root or the current user that no group or other user can write.
    /// A brew somebody else could have replaced is not run.
    static func isTrusted(_ facts: Facts, currentUID: UInt32) -> Bool {
        facts.isRegularFile && facts.isExecutable
            && (facts.ownerUID == 0 || facts.ownerUID == currentUID)
            && facts.mode & 0o022 == 0
    }

    static func locate(candidates: [String], inspect: (String) -> Facts?, currentUID: UInt32) -> String? {
        candidates.first { path in
            inspect(path).map { isTrusted($0, currentUID: currentUID) } ?? false
        }
    }

    /// The brew to run, nil when Homebrew is not installed (or the file looks tampered with).
    static func locate() -> String? {
        locate(candidates: candidates(environment: ProcessInfo.processInfo.environment),
               inspect: inspect, currentUID: UInt32(getuid()))
    }

    static func inspect(_ path: String) -> Facts? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return Facts(isRegularFile: (info.st_mode & S_IFMT) == S_IFREG,
                     isExecutable: access(path, X_OK) == 0,
                     ownerUID: info.st_uid,
                     mode: UInt16(info.st_mode & 0o7777))
    }

    private static func isCleanAbsolute(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.contains("..") && !path.contains("\0") && !path.contains("\n")
            && path.range(of: #"^[A-Za-z0-9._+@/ -]+$"#, options: .regularExpression) != nil
    }
}

// MARK: - Cleanup (brew cleanup, with its own dry run first)

/// `brew cleanup`: removes old versions of installed formulae and stale downloads. Upstream has no such action;
/// it is added here with a preview, because it deletes. The preview is brew's own `cleanup --dry-run`, shown
/// whole, and the real run happens only after the person confirmed THAT preview.
enum HomebrewCleanup {
    struct Entry: Equatable, Identifiable {
        let path: String
        /// What brew says in the parentheses: a size, or "12 files, 3.4MB".
        let detail: String
        var id: String { path }
    }

    struct Preview: Equatable {
        var entries: [Entry]
        /// The size brew says the run would free ("1.2GB"), when it says one.
        var freeable: String?
        var isEmpty: Bool { entries.isEmpty }
    }

    /// Fixed argument arrays. No `--prune=all`, no `-s`, no formula names: the plain cleanup, nothing else.
    static func previewCommand(brewPath: String) -> HomebrewCommand {
        HomebrewCommand(executable: brewPath, arguments: ["cleanup", "--dry-run"])
    }

    static func runCommand(brewPath: String) -> HomebrewCommand {
        HomebrewCommand(executable: brewPath, arguments: ["cleanup"])
    }

    /// Reads the output of `brew cleanup --dry-run`. Only absolute paths without `..` count as entries.
    static func parse(_ output: String) -> Preview {
        var entries: [Entry] = []
        var freeable: String?
        for raw in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Would remove: ") {
                let rest = String(line.dropFirst("Would remove: ".count))
                var path = rest
                var detail = ""
                if rest.hasSuffix(")"), let open = rest.range(of: " (", options: .backwards) {
                    path = String(rest[..<open.lowerBound])
                    detail = String(rest[open.upperBound...].dropLast())
                }
                guard path.hasPrefix("/"), !path.contains(".."), !path.contains("\0"),
                      !entries.contains(where: { $0.path == path }) else { continue }
                entries.append(Entry(path: path, detail: detail))
            } else if let range = line.range(of: #"approximately (\S+) of disk space"#, options: .regularExpression) {
                let words = line[range].split(separator: " ")
                if words.count >= 2 { freeable = String(words[1]) }
            }
        }
        return Preview(entries: entries, freeable: freeable)
    }
}

/// The cleanup flow: preview, confirm, run. Everything external goes through `run` and `locate`, so a test drives
/// it with fakes and never starts brew.
@MainActor
final class HomebrewCleanupModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case brewMissing
        case previewing
        case preview(HomebrewCleanup.Preview)
        case running
        case finished(String)
        case failed(String)
    }

    struct RunResult: Equatable {
        var status: Int32
        var output: String
        var timedOut: Bool
    }

    typealias Runner = @Sendable (HomebrewCommand, BoundedProcessCancellation) async -> RunResult

    @Published private(set) var phase: Phase = .idle

    private let locate: @MainActor () -> String?
    private let run: Runner
    private let managerBusy: @MainActor () -> Bool
    private var generation = 0
    /// The brew the preview came from: the real run uses the very same one.
    private var previewedBrew: String?
    private var cancellation = BoundedProcessCancellation()

    init(locate: @escaping @MainActor () -> String?, run: @escaping Runner, managerBusy: @escaping @MainActor () -> Bool) {
        self.locate = locate
        self.run = run
        self.managerBusy = managerBusy
    }

    static let shared = HomebrewCleanupModel(
        locate: { BrewLocator.locate() },
        run: HomebrewCleanupModel.liveRun,
        managerBusy: { HomebrewManager.shared.operation != nil })

    /// The real runner: a bounded child, no shell, the sanitized brew environment, output capped.
    static let liveRun: Runner = { command, cancellation in
        await Task.detached(priority: .utility) {
            let result = BoundedProcessRunner.run(command.executable, command.arguments,
                                                  timeout: 180, maxOutputBytes: 1_048_576,
                                                  environment: HomebrewEnvironment.forBrew,
                                                  cancellation: cancellation)
            return RunResult(status: result.status, output: String(decoding: result.output, as: UTF8.self),
                             timedOut: result.timedOut)
        }.value
    }

    var isBusy: Bool {
        switch phase {
        case .previewing, .running: true
        default: false
        }
    }

    /// Step 1: brew's own dry run. Removes nothing.
    func preview() async {
        guard !isBusy, !managerBusy() else { return }
        guard let brew = locate() else {
            phase = .brewMissing
            return
        }
        generation += 1
        let mine = generation
        cancellation = BoundedProcessCancellation()
        phase = .previewing
        let result = await run(HomebrewCleanup.previewCommand(brewPath: brew), cancellation)
        guard mine == generation else { return }
        if result.timedOut {
            phase = .failed(HomebrewCleanupText.timedOut)
        } else if result.status != 0 {
            phase = .failed(Self.firstLine(of: result.output))
        } else {
            previewedBrew = brew
            phase = .preview(HomebrewCleanup.parse(result.output))
        }
    }

    /// Step 2: the real cleanup. Only from a preview that listed something, with the same brew, while no other
    /// brew operation runs.
    func confirm() async {
        guard case let .preview(shown) = phase, !shown.isEmpty, let brew = previewedBrew,
              locate() == brew, !managerBusy() else { return }
        generation += 1
        let mine = generation
        cancellation = BoundedProcessCancellation()
        phase = .running
        let result = await run(HomebrewCleanup.runCommand(brewPath: brew), cancellation)
        guard mine == generation else { return }
        previewedBrew = nil
        if result.timedOut {
            phase = .failed(HomebrewCleanupText.timedOut)
        } else if result.status != 0 {
            phase = .failed(Self.firstLine(of: result.output))
        } else {
            phase = .finished(shown.freeable.map { HomebrewCleanupText.freed($0) } ?? HomebrewCleanupText.done)
        }
    }

    /// Drops a shown preview, or stops a running command (the kill switch, the Annuler button).
    func cancel() {
        generation += 1
        cancellation.cancel()
        previewedBrew = nil
        phase = .idle
    }

    private static func firstLine(of output: String) -> String {
        let line = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        return line ?? HomebrewCleanupText.failedGeneric
    }
}

// MARK: - Upgrade preview

/// The list the "Tout mettre à jour" confirmation shows under its sentence: every package `brew outdated` reports,
/// with its installed and its new version. Pinned packages are left out, as `brew upgrade` leaves them out.
enum HomebrewUpgradePreview {
    static let defaultLimit = 12

    static func lines(_ updates: [HomebrewPackageUpdate], limit: Int = defaultLimit) -> [String] {
        let sorted = updates.filter { !$0.isPinned }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        var lines = sorted.prefix(limit).map { "\($0.name) : \($0.installedText) → \($0.currentVersion)" }
        if sorted.count > limit {
            let rest = sorted.count - limit
            lines.append(rest == 1 ? "… et 1 autre" : "… et \(rest) autres")
        }
        return lines
    }

    static func message(base: String, updates: [HomebrewPackageUpdate], limit: Int = defaultLimit) -> String {
        let shown = lines(updates, limit: limit)
        return shown.isEmpty ? base : base + "\n\n" + shown.joined(separator: "\n")
    }
}

// MARK: - Texts

enum HomebrewCleanupText {
    static let title = "Nettoyer Homebrew"
    static let caption = "Supprime les anciennes versions des formules installées et les téléchargements devenus inutiles. "
        + "Mac Island montre d’abord ce que brew supprimerait, puis ne lance le nettoyage qu’après votre accord."
    static let previewButton = "Voir ce qui serait supprimé"
    static let previewing = "Analyse en cours…"
    static let running = "Nettoyage en cours…"
    static let nothing = "Rien à nettoyer : Homebrew n’a rien de superflu."
    static let confirm = "Nettoyer maintenant"
    static let cancel = "Annuler"
    static let brewMissing = "Homebrew est introuvable sur ce Mac."
    static let busy = "Une autre opération Homebrew est en cours."
    static let timedOut = "Homebrew n’a pas répondu à temps. Réessayez plus tard."
    static let failedGeneric = "Le nettoyage n’a pas abouti."
    static let done = "Nettoyage terminé."
    static let again = "Recommencer"

    static func entries(_ count: Int) -> String {
        count == 1 ? "1 élément serait supprimé" : "\(count) éléments seraient supprimés"
    }

    static func freed(_ size: String) -> String { "Nettoyage terminé : environ \(size) libérés." }
    static func freeable(_ size: String) -> String { "Espace libéré estimé par brew : \(size)." }
}

enum AppUpdatesText {
    static let notificationNote = "Mac Island ne demande jamais l’autorisation lui-même. "
        + "Si aucune notification n’apparaît, autorisez-la dans les réglages du Mac."
    static let notificationButton = "Ouvrir les réglages de notifications"
}

// MARK: - Views

/// Page "homebrew": the ported manager (search, installed, outdated, upgrade, uninstall) and the cleanup card.
private struct HomebrewPage: View {
    var body: some View {
        VStack(spacing: 12) {
            HomebrewCleanupCard()
                .padding(.horizontal, 16)
                .padding(.top, 12)
            HomebrewSettings()
        }
    }
}

/// The cleanup card: a frosted surface with the two steps in plain French.
struct HomebrewCleanupCard: View {
    @ObservedObject private var model = HomebrewCleanupModel.shared
    @ObservedObject private var homebrew = HomebrewManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(HomebrewCleanupText.title, systemImage: "sparkles")
                .font(.headline)
            Text(HomebrewCleanupText.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .islandGlass(cornerRadius: IslandRadius.medium)
        .onDisappear {
            // A preview left on screen is stale the next time the page opens.
            if case .preview = model.phase { model.cancel() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            startButton
        case .brewMissing:
            note(HomebrewCleanupText.brewMissing, color: .orange)
            startButton
        case .previewing:
            progress(HomebrewCleanupText.previewing)
        case let .preview(shown):
            previewBody(shown)
        case .running:
            progress(HomebrewCleanupText.running)
        case let .finished(message):
            note(message, color: .green)
            startButton(title: HomebrewCleanupText.again)
        case let .failed(message):
            note(message, color: .orange)
            startButton(title: HomebrewCleanupText.again)
        }
    }

    private var startButton: some View { startButton(title: HomebrewCleanupText.previewButton) }

    private func startButton(title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(title) { Task { await model.preview() } }
                .disabled(homebrew.operation != nil)
            if homebrew.operation != nil {
                Text(HomebrewCleanupText.busy).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button(HomebrewCleanupText.cancel) { model.cancel() }
        }
    }

    private func note(_ text: String, color: Color) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.callout)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func previewBody(_ shown: HomebrewCleanup.Preview) -> some View {
        if shown.isEmpty {
            note(HomebrewCleanupText.nothing, color: .secondary)
            startButton(title: HomebrewCleanupText.again)
        } else {
            Text(HomebrewCleanupText.entries(shown.entries.count))
                .font(.callout.weight(.medium))
            if let size = shown.freeable {
                Text(HomebrewCleanupText.freeable(size)).font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(shown.entries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(entry.path)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            if !entry.detail.isEmpty {
                                Text(entry.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 180)
            HStack {
                Button(HomebrewCleanupText.cancel) { model.cancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(HomebrewCleanupText.confirm) { Task { await model.confirm() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(homebrew.operation != nil)
            }
        }
    }
}

/// Under the notification switch of the app updates page: the page no longer raises the system prompt, so it says
/// where to allow notifications instead.
struct AppUpdatesNotificationHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppUpdatesText.notificationNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(AppUpdatesText.notificationButton) { Permissions.shared.openNotificationSettings() }
                .controlSize(.small)
        }
    }
}
