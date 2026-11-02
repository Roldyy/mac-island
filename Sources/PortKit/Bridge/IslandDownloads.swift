// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W8C (downloads, file tools, watch, mirror). The lane owns this file.

import AppKit
import Combine
import IslandKit
import SwiftUI

// MARK: - Downloads: what the closed island shows

/// The closed-island activity of the downloads folder. Pure: the feed below calls it, the tests call it.
///
/// A transfer in progress is a quiet `ambient` activity (a ring on the left, a count or a percentage on the right); the
/// end of one is a short `music`-rank "Terminé" or "Échec", gone after a few seconds. Nothing outranks Claude, and with
/// nothing downloading nothing is posted.
enum IslandDownloadActivity {
    static let source = "notchDownloads"
    static let progressID = "downloads.progress"
    static let doneID = "downloads.done"
    static let failedID = "downloads.failed"
    static let resultLifetime: Duration = .seconds(6)

    static func progress(_ items: [NotchDownloadItem]) -> IslandActivity? {
        let running = items.filter { !$0.completed && $0.active }
        guard !running.isEmpty else { return nil }
        let fractions = running.compactMap(\.fraction).filter(\.isFinite)
        let progress = fractions.isEmpty ? nil : min(1, max(0, fractions.reduce(0, +) / Double(fractions.count)))
        let text = running.count > 1 ? "\(running.count)" : progress.map { "\(Int(($0 * 100).rounded())) %" }
        return IslandActivity(
            id: progressID, source: source, priority: .ambient,
            leading: CompactItem(symbol: "arrow.down.circle", status: .info, progress: progress),
            trailing: text.map { CompactItem(symbol: "arrow.down", text: $0, status: .info) })
    }

    static func finished() -> IslandActivity {
        IslandActivity(id: doneID, source: source, priority: .music,
                       leading: CompactItem(symbol: "checkmark.circle", status: .success),
                       trailing: CompactItem(symbol: "arrow.down", text: "Terminé", status: .success))
    }

    static func failed() -> IslandActivity {
        IslandActivity(id: failedID, source: source, priority: .music,
                       leading: CompactItem(symbol: "exclamationmark.triangle", status: .warning),
                       trailing: CompactItem(symbol: "arrow.down", text: "Échec", status: .warning))
    }
}

/// Follows the downloads service and keeps the board current. The service stays the only source of truth.
@MainActor
final class IslandDownloadsFeed {
    private let items: AnyPublisher<[NotchDownloadItem], Never>
    private let board: IslandActivityBoard
    private var subscription: AnyCancellable?

    init(items: AnyPublisher<[NotchDownloadItem], Never>, board: IslandActivityBoard) {
        self.items = items
        self.board = board
    }

    var isRunning: Bool { subscription != nil }

    func start() {
        guard subscription == nil else { return }
        board.register(IslandActivitySource(id: IslandDownloadActivity.source, title: "Téléchargements",
                                            symbol: "arrow.down.circle"))
        subscription = items.sink { [weak self] items in self?.apply(items) }
    }

    func apply(_ items: [NotchDownloadItem]) {
        if let activity = IslandDownloadActivity.progress(items) {
            board.post(activity)
        } else {
            board.withdraw(id: IslandDownloadActivity.progressID)
        }
    }

    func arrived() { board.post(IslandDownloadActivity.finished(), expiresAfter: IslandDownloadActivity.resultLifetime) }

    func failed() { board.post(IslandDownloadActivity.failed(), expiresAfter: IslandDownloadActivity.resultLifetime) }

    func stop() {
        subscription = nil
        board.withdrawAll(source: IslandDownloadActivity.source)
    }
}

// MARK: - Watch: what the closed island shows

/// The closed-island activity of a watch (a part of a window read every second or two).
enum IslandWatchActivity {
    static let source = "notchWatch"
    static let id = "watch.state"
    static let resultLifetime: Duration = .seconds(12)
    static let maximumReading = 14

    /// `title` names an outcome in the person's language (upstream's own table); a test passes its own.
    static func activity(state: NotchWatchState, headline: String, title: (NotchWatchOutcome) -> String) -> IslandActivity? {
        switch state {
        case .idle:
            return nil
        case .watching:
            let reading = clip(headline)
            return IslandActivity(id: id, source: source, priority: .ambient,
                                  leading: CompactItem(symbol: "eye", status: .info),
                                  trailing: reading.map { CompactItem(symbol: "text.viewfinder", text: $0, status: .info) })
        case .hidden:
            return IslandActivity(id: id, source: source, priority: .ambient,
                                  leading: CompactItem(symbol: "eye.slash", status: .neutral),
                                  trailing: CompactItem(symbol: "macwindow", text: "Masquée", status: .neutral))
        case .finished(let outcome):
            // The person asked to be told: this one outranks everything else on the island.
            return IslandActivity(id: id, source: source, priority: .alert,
                                  leading: CompactItem(symbol: "eye", status: .success),
                                  trailing: CompactItem(symbol: "checkmark.circle", text: clip(title(outcome)), status: .success),
                                  showsDot: true)
        }
    }

    static func clip(_ text: String) -> String? {
        let one = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !one.isEmpty else { return nil }
        return one.count > maximumReading ? String(one.prefix(maximumReading - 1)) + "…" : one
    }
}

@MainActor
final class IslandWatchFeed {
    private let state: AnyPublisher<(NotchWatchState, String), Never>
    private let board: IslandActivityBoard
    private let title: (NotchWatchOutcome) -> String
    private var subscription: AnyCancellable?

    init(state: AnyPublisher<(NotchWatchState, String), Never>, board: IslandActivityBoard,
         title: @escaping (NotchWatchOutcome) -> String) {
        self.state = state
        self.board = board
        self.title = title
    }

    var isRunning: Bool { subscription != nil }

    func start() {
        guard subscription == nil else { return }
        board.register(IslandActivitySource(id: IslandWatchActivity.source, title: "Surveillance", symbol: "eye"))
        subscription = state.sink { [weak self] state, headline in self?.apply(state, headline: headline) }
    }

    func apply(_ state: NotchWatchState, headline: String) {
        guard let activity = IslandWatchActivity.activity(state: state, headline: headline, title: title) else {
            board.withdraw(id: IslandWatchActivity.id)
            return
        }
        if case .finished = state {
            board.post(activity, expiresAfter: IslandWatchActivity.resultLifetime)
        } else {
            board.post(activity)
        }
    }

    func stop() {
        subscription = nil
        board.withdrawAll(source: IslandWatchActivity.source)
    }
}

// MARK: - The lane

/// Binds the two ported island features of wave 8C: `notchDownloads` (the downloads folder) and `notchWatch` (a window
/// area read on the Mac itself). Both are new to Mac Island and OFF until the person switches them on in Fonctions.
///
/// What the registry does, all through `Runtime` so tests never touch a folder watcher, Vision or a window list:
/// - start = take the "hosting" flag (so the ported checks answer for OUR island, see `IslandActivityHost`), start the feed
///   that turns the service's state into closed-island activities, then the service's own sync, which arms only what the
///   person set up (a downloads folder chosen with the system's folder panel; a watch they started on its page);
/// - stop (switch off, kill switch, safe mode, quarantine) = the service's own stop, the feed's end (everything it posted
///   is withdrawn) and the flag released. Nothing is built by a stop that follows no start.
///
/// The watch needs Screen Recording: the binding does not start it without, and never asks (Permissions open the pane).
/// The downloads folder is a bookmark chosen in the system panel: Vorssaint's old bookmark was never migrated, the person
/// picks the folder again (their `Downloads` is the panel's first suggestion).
///
/// The Files page (file tools: archive, optimise media) and the Mirror page are tabs (`IslandPortTabs`), not features:
/// the shelf, Media Tools and the camera preview stay their own switches.
enum IslandDownloadsLane {
    struct Runtime {
        var startDownloads: @MainActor () -> Void
        var stopDownloads: @MainActor () -> Void
        var startWatch: @MainActor () -> Void
        var stopWatch: @MainActor () -> Void

        @MainActor private static var downloadsFeed: IslandDownloadsFeed?
        @MainActor private static var watchFeed: IslandWatchFeed?

        static let live = Runtime(
            startDownloads: {
                IslandActivityHost.shared.acquire(IslandDownloadActivity.source)
                let service = NotchDownloadService.shared
                let feed = downloadsFeed ?? IslandDownloadsFeed(
                    items: service.$items.receive(on: DispatchQueue.main).eraseToAnyPublisher(), board: .shared)
                downloadsFeed = feed
                service.onArrival = { [weak feed] _ in Task { @MainActor in feed?.arrived() } }
                service.onFailure = { [weak feed] in Task { @MainActor in feed?.failed() } }
                feed.start()
                service.syncWithPreferences()
            },
            stopDownloads: {
                if let feed = downloadsFeed {
                    NotchDownloadService.shared.stop()
                    NotchDownloadService.shared.onArrival = nil
                    NotchDownloadService.shared.onFailure = nil
                    feed.stop()
                }
                IslandActivityHost.shared.release(IslandDownloadActivity.source)
            },
            startWatch: {
                IslandActivityHost.shared.acquire(IslandWatchActivity.source)
                let service = NotchWatchService.shared
                let feed = watchFeed ?? IslandWatchFeed(
                    state: service.$state.combineLatest(service.$headline)
                        .receive(on: DispatchQueue.main).eraseToAnyPublisher(),
                    board: .shared,
                    title: { FeatureStrings.notchWatch(L10n.shared.language).outcome($0) })
                watchFeed = feed
                feed.start()
                service.syncWithPreferences()
            },
            stopWatch: {
                if let feed = watchFeed {
                    NotchWatchService.shared.stop()
                    feed.stop()
                }
                IslandActivityHost.shared.release(IslandWatchActivity.source)
            })
    }

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        binding.bind("notchDownloads", start: { runtime.startDownloads() }, stop: { runtime.stopDownloads() })
        binding.bind("notchWatch", start: { runtime.startWatch() }, stop: { runtime.stopWatch() })
    }
}

// MARK: - Tabs for the island

/// The pages of wave 8C as `IslandTab`s for the island's tab list, built from the ported views. Each one only reads: a tab
/// whose feature is off shows one French line pointing at Fonctions and builds none of the ported services.
public enum IslandPortTabs {
    /// The tabs of this lane, in the order the island lists them.
    @MainActor public static func lane8C() -> [IslandTab] { [downloads(), fileTools(), watch(), mirror()] }

    @MainActor public static func downloads() -> IslandTab {
        IslandTab(id: "downloads", title: "Téléchargements", systemImage: "arrow.down.circle") {
            AnyView(IslandPortGate(feature: IslandDownloadActivity.source, title: "Téléchargements") {
                GeometryReader { NotchDownloadsView(size: $0.size) }
            })
        }
    }

    /// Archive and optimise what was dropped: the ported Files page (it needs the shelf and Media Tools on).
    @MainActor public static func fileTools() -> IslandTab {
        IslandTab(id: "filetools", title: "Fichiers", systemImage: "tray.full") {
            AnyView(IslandFilesGate {
                NotchFilesView(service: NotchService.shared)
                    .onAppear { IslandActivityHost.shared.acquire("fileTools") }
                    .onDisappear { IslandActivityHost.shared.release("fileTools") }
            })
        }
    }

    @MainActor public static func watch() -> IslandTab {
        IslandTab(id: "watch", title: "Surveillance", systemImage: "eye") {
            AnyView(IslandPortGate(feature: IslandWatchActivity.source, title: "Surveillance") {
                GeometryReader { NotchWatchView(size: $0.size) }
            })
        }
    }

    /// The camera mirror (the ported camera preview, embedded). The "Miroir" feature stays its switch; the page holds the
    /// "mirror" host only while it is on screen, and leaving it releases the capture session (`NotchCameraView`).
    @MainActor public static func mirror() -> IslandTab {
        IslandTab(id: "mirror", title: "Miroir", systemImage: "web.camera") {
            AnyView(GeometryReader { NotchCameraView(size: $0.size) }
                .onAppear { IslandActivityHost.shared.acquire(IslandMirrorTab.owner) }
                .onDisappear { IslandActivityHost.shared.release(IslandMirrorTab.owner) })
        }
    }
}

enum IslandMirrorTab {
    static let owner = "mirror"
}

/// The Fichiers page works on the shelf's files: with the shelf off it says so in French instead of drawing a page that
/// cannot do anything (the ported page reads `AppFeature.shelf`, which is the registry's verdict for our shelf).
private struct IslandFilesGate<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @ObservedObject private var ticker = IslandHostTicker.shared
    @ObservedObject private var features = FeatureRuntime.shared

    var body: some View {
        if features.isAvailable(.shelf) {
            content()
        } else {
            VStack(spacing: 8) {
                Image(systemName: "tray").font(.system(size: 22, weight: .light))
                Text("« Fichiers » a besoin de l’Étagère. Allumez-la dans Fonctions pour archiver ou optimiser des fichiers ici.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Shows the page only while the registry has the feature running.
private struct IslandPortGate<Content: View>: View {
    let feature: String
    let title: String
    @ViewBuilder let content: () -> Content
    @ObservedObject private var ticker = IslandHostTicker.shared

    var body: some View {
        if IslandActivityHost.shared.holds(feature) {
            content()
        } else {
            VStack(spacing: 8) {
                Image(systemName: "switch.2").font(.system(size: 22, weight: .light))
                Text("« \(title) » est éteint. Allumez-le dans Fonctions pour l’utiliser ici.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Settings

/// The two Downloads switches of the old Étagère page, back on the ported shelf page: whether the Downloads segment of the
/// Étagère tab lists recent files, and how many. They are the keys that segment already reads (`shelfDownloadsEnabled`,
/// `shelfDownloadsLimit`, `Sources/Features/Shelf/ShelfSettings.swift`), so the switches work today. Below them, the
/// folder and the options of the downloads page of the island (`notchDownloads`), upstream's own controls.
struct IslandShelfDownloadsSettings: View {
    @AppStorage("shelfDownloadsEnabled") private var listsDownloads = true
    @AppStorage("shelfDownloadsLimit") private var limit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Téléchargements").font(.headline)
            Toggle("Montrer les téléchargements récents", isOn: $listsDownloads)
            Text("Les derniers fichiers téléchargés apparaissent sur l’étagère.")
                .font(.caption).foregroundStyle(.secondary)
            Stepper(value: $limit, in: 1...50) {
                Text("Nombre de téléchargements affichés : \(limit)")
            }
            .disabled(!listsDownloads)
            .accessibilityLabel("Nombre de téléchargements affichés")
            Divider()
            NotchDownloadsSettingsControls()
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
