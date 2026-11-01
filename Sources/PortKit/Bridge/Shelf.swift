// SPDX-License-Identifier: GPL-3.0-or-later
// Lane W5B (shelf, scratchpad, plain text editor). The lane owns this file.

import AppKit
import IslandKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shelf lane

/// Binds the ported Shelf, which REPLACES our `Sources/Features/Shelf` item store, and the ported Scratchpad.
///
/// The Shelf: the registry keeps OUR descriptor (`shelf`: title, switch, island tab, Home tile, migrated
/// `shell.enabled.shelf`), so the binding adds none. The ported service owns the items (`shelfItems` in the app's
/// defaults, upstream's JSON) and the floating shelf (shortcut, shake, drop zone, edge peek). What the registry does,
/// all through `Runtime` so tests never touch a hotkey, a mouse monitor or a panel:
/// - start = the one-time import of our own store (`ShelfLegacyMigration`), then `ShelfService.syncWithPreferences()`,
///   which arms only what the person's options allow (a Carbon hot key and passive mouse monitors: no permission,
///   never a prompt);
/// - stop (switch off, kill switch, safe mode, quarantine) = the same sync after the binding denied the feature, so
///   the shortcut, the monitors and every panel go. The service is never built by a stop that follows no start.
///
/// The island's Étagère tab (`Sources/Features/Shelf`) hosts the ported items through `PortShelf.strip()`: one store,
/// shown in two places. The Downloads segment of that tab stays ours until wave 8 (`NotchDownloads`).
///
/// The Scratchpad is a new feature (`scratchpad`, off until the person switches it on). It reads the very
/// `Scratchpad.json` our Clipboard module wrote since the migration: `ScratchpadLegacyBackup` copies that file once
/// before the ported store can rewrite it in its own codec.
enum ShelfLane {
    /// What the lane does to the upstream services. The registry tests swap it for a fake.
    struct Runtime {
        /// Imports our own store into the ported one, once. Always runs BEFORE the first touch of `ShelfService`.
        var prepareStore: @MainActor () -> Void
        var sync: @MainActor () -> Void
        var stop: @MainActor () -> Void

        @MainActor private static var touched = false

        static let live = Runtime(
            prepareStore: { ShelfLane.prepareStore() },
            sync: { touched = true; ShelfService.shared.syncWithPreferences() },
            stop: { if touched { ShelfService.shared.syncWithPreferences() } })
    }

    static let shelfPageID = "shelf"

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live, scratchpad: .live)
        installPages()
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime, scratchpad: ScratchpadLane.Runtime) {
        binding.bindReplacing(
            "shelf",
            start: {
                runtime.prepareStore()
                runtime.sync()
            },
            stop: { runtime.stop() })
        ScratchpadLane.bind(into: binding, runtime: scratchpad)
    }

    private static var didInstallPages = false

    @MainActor private static func installPages() {
        guard !didInstallPages else { return }
        didInstallPages = true
        // The catalog row `shelf` already carries the shelf's feature card: a plain page body.
        PortBridge.register(pageID: shelfPageID) { AnyView(ShelfSettings().defaultAppStorage(PortHost.defaults)) }
    }

    @MainActor private static var didPrepare = false

    /// Runs the one-time import before the ported service is first built (it restores `shelfItems` when it is).
    /// Idempotent for the process; the import itself is idempotent across launches (its marker).
    @MainActor static func prepareStore(defaults: UserDefaults = PortHost.defaults,
                                        directory: URL? = PrivateFileStore.containerURL) {
        guard !didPrepare else { return }
        didPrepare = true
        guard let directory else { return }
        _ = ShelfLegacyMigration.run(dataDirectory: directory, defaults: defaults)
    }
}

// MARK: - One-time import of our own shelf store

/// Mac Island's own Shelf (until this lane) kept its items in `<Data>/Shelf.json`:
/// `[{"id": UUID, "path": String, "bookmark": base64?, "addedAt": seconds}]`. It never wrote `shelfItems`, which
/// holds upstream's format (`[ShelfPersistedItem]`, an array with a `kind` per entry): the ported store reads our
/// old entries as unreadable (`kind` is missing), so they are converted here, once.
///
/// Safety, in the order it acts:
/// - nothing runs twice (`markerKey`, written only after the result was read back);
/// - `Shelf.json` is copied to `Shelf.pre-port.json` (owner-only, never overwritten) before anything is written, and
///   `Shelf.json` itself is never deleted or rewritten: it is the original;
/// - a `shelfItems` the ported store cannot read whole is left alone (the import stops, the marker stays unset, the
///   next launch tries again), so a store written by a newer build is never overwritten;
/// - an entry already on the shelf (same path) is not added twice;
/// - the files the entries point at are never touched: an item is a path and a bookmark, not a copy.
enum ShelfLegacyMigration {
    static let markerKey = "migration.shelf.port.done"
    static let legacyFileName = "Shelf.json"
    static let backupFileName = "Shelf.pre-port.json"

    enum Outcome: Equatable {
        case alreadyDone
        /// No `Shelf.json`, or one with no entry: nothing to carry.
        case nothingToImport
        case imported(added: Int)
        /// `Shelf.json` is not a list this build can read: left as it is, retried at the next launch.
        case legacyUnreadable
        /// `shelfItems` holds something the ported store cannot read whole: left as it is, retried at the next launch.
        case shelfItemsUnreadable
        /// The backup could not be written, so nothing else was.
        case backupFailed
        /// The converted list did not read back as written: `shelfItems` was put back as it was.
        case verificationFailed
    }

    struct LegacyEntry: Equatable {
        let id: UUID
        let path: String
        let bookmark: Data?
    }

    /// Our entries, tolerant per entry (one broken entry never hides the others). nil when the data is not a list.
    static func legacyEntries(from data: Data) -> [LegacyEntry]? {
        struct Lossy: Decodable {
            let entry: LegacyEntry?
            init(from decoder: Decoder) throws {
                enum Keys: String, CodingKey { case id, path, bookmark }
                // The path is the entry; a bad id or bookmark only costs the id (renewed) or the bookmark.
                guard let box = try? decoder.container(keyedBy: Keys.self),
                      let path = (try? box.decodeIfPresent(String.self, forKey: .path)) ?? nil, !path.isEmpty else {
                    entry = nil
                    return
                }
                let id = (try? box.decodeIfPresent(UUID.self, forKey: .id)) ?? nil
                let bookmark = (try? box.decodeIfPresent(Data.self, forKey: .bookmark)) ?? nil
                entry = LegacyEntry(id: id ?? UUID(), path: path, bookmark: bookmark)
            }
        }
        guard let list = try? JSONDecoder().decode([Lossy].self, from: data) else { return nil }
        var seen = Set<String>()
        return list.compactMap(\.entry).filter { seen.insert($0.path).inserted }
    }

    /// Our entries in upstream's persisted form.
    static func persisted(_ entries: [LegacyEntry]) -> [ShelfPersistedItem] {
        entries.map {
            ShelfPersistedItem(id: $0.id, kind: .file, title: URL(fileURLWithPath: $0.path).lastPathComponent,
                               path: $0.path, bookmark: $0.bookmark)
        }
    }

    /// Owner-only write that reads back what it wrote (a test swaps it for one that fails).
    static let writeBackupFile: (Data, URL) -> Bool = { data, url in
        PrivateFileStore.write(data, to: url) && (try? Data(contentsOf: url)) == data
    }

    static func run(dataDirectory: URL, defaults: UserDefaults, fileManager: FileManager = .default,
                    writeBackup: (Data, URL) -> Bool = writeBackupFile) -> Outcome {
        guard !defaults.bool(forKey: markerKey) else { return .alreadyDone }
        let source = dataDirectory.appendingPathComponent(legacyFileName)
        guard fileManager.fileExists(atPath: source.path) else {
            defaults.set(true, forKey: markerKey)
            return .nothingToImport
        }
        guard let data = try? Data(contentsOf: source), let entries = legacyEntries(from: data) else {
            return .legacyUnreadable
        }
        guard !entries.isEmpty else {
            defaults.set(true, forKey: markerKey)
            return .nothingToImport
        }

        // What the ported store holds now. Only a blob it reads whole may be extended.
        let previous = defaults.object(forKey: DefaultsKey.shelfItems)
        let existingData: Data?
        switch previous {
        case nil: existingData = nil
        case let blob as Data: existingData = blob
        default: return .shelfItemsUnreadable
        }
        let existing: [ShelfPersistedItem]
        switch ShelfPersistenceSupport.load(existingData) {
        case let .items(items): existing = items
        case .partial, .unreadable: return .shelfItemsUnreadable
        }

        // The backup comes first and is never replaced: the first copy is the pre-port state.
        let backup = dataDirectory.appendingPathComponent(backupFileName)
        if !fileManager.fileExists(atPath: backup.path) {
            guard writeBackup(data, backup) else { return .backupFailed }
        }

        let known = paths(in: existing)
        let additions = persisted(entries.filter { !known.contains($0.path) })
        let merged = existing + additions
        guard let encoded = try? JSONEncoder().encode(merged) else { return .verificationFailed }
        defaults.set(encoded, forKey: DefaultsKey.shelfItems)
        guard case let .items(readBack) = ShelfPersistenceSupport.load(defaults.data(forKey: DefaultsKey.shelfItems)),
              readBack == merged else {
            if let previous { defaults.set(previous, forKey: DefaultsKey.shelfItems) }
            else { defaults.removeObject(forKey: DefaultsKey.shelfItems) }
            return .verificationFailed
        }
        defaults.set(true, forKey: markerKey)
        return .imported(added: additions.count)
    }

    private static func paths(in items: [ShelfPersistedItem]) -> Set<String> {
        items.reduce(into: Set<String>()) { result, item in
            if let path = item.path { result.insert(path) }
            result.formUnion(paths(in: item.children ?? []))
        }
    }
}

// MARK: - Island tab: items, drops

/// What the island's Étagère tab hosts. The tab itself (title, icon, the Downloads segment) stays in
/// `Sources/Features/Shelf`; the items are the ported service's.
public enum PortShelf {
    /// The Étagère segment of the island tab: the ported tiles (drag several out at once, pin, batches, selection)
    /// in the island's sideways strip, plus a drop target. Never builds the service while the feature is off.
    @MainActor public static func strip() -> AnyView { AnyView(ShelfIslandStripGate()) }
}

/// Only reads the registry's verdict, so a Mac where the shelf is off never builds `ShelfService`.
private struct ShelfIslandStripGate: View {
    var body: some View {
        if AppFeature.shelf.isAvailable, PortHost.defaults.bool(forKey: DefaultsKey.shelfEnabled) {
            ShelfIslandStrip()
        } else {
            Text("L'étagère est désactivée dans les réglages.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ShelfIslandStrip: View {
    @ObservedObject private var shelf: ShelfService
    @ObservedObject private var l10n = L10n.shared
    @State private var isTargeted = false

    init() {
        ShelfLane.prepareStore()  // the import runs before the service restores `shelfItems`
        _shelf = ObservedObject(wrappedValue: ShelfService.shared)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if shelf.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 22, weight: .light))
                    Text(l10n.s.shelfEmpty).font(.caption)
                }
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("\(shelf.itemCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Button(l10n.s.shelfClearAll, systemImage: "trash") { shelf.clear() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                ShelfTilesView(items: shelf.visibleItems,
                               contentRevision: shelf.contentRevision,
                               selection: shelf.selection,
                               expandedBatches: shelf.expandedBatches,
                               pinnedIDs: shelf.pinnedIDs,
                               revealID: shelf.revealTargetID,
                               revealSerial: shelf.addSerial,
                               sideways: true)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(isTargeted ? 0.6 : 0.12), style: StrokeStyle(lineWidth: 1, dash: [4]))
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        // SwiftUI's drop is what already works on the island's non-activating panel (.screenSaver level): the
        // decision is `ShelfIslandDrop`, which a test drives with fakes.
        .onDrop(of: ShelfIslandDrop.acceptedTypes, isTargeted: $isTargeted) { providers in
            ShelfIslandDrop.handle(providers.map(ShelfItemProvider.init), into: LiveShelfDropSink())
        }
        .accessibilityLabel(l10n.s.shelfTitle)
    }
}

/// One dragged item as the drop logic sees it, so a test never needs a real `NSItemProvider`.
protocol ShelfDropProviding: Sendable {
    /// True when the item can give a file URL.
    var carriesFileURL: Bool { get }
    /// Answers once with the file URL, nil when it cannot give one.
    func loadFileURL(_ done: @escaping @Sendable (URL?) -> Void)
}

/// Where accepted file URLs go.
@MainActor protocol ShelfDropSink: Sendable {
    /// False while the feature is off or its own setting is off: such a drop is refused at once.
    var acceptsDrops: Bool { get }
    /// Adds the files (several of one drop become one batch). True when something was added.
    func add(_ urls: [URL]) -> Bool
}

struct ShelfItemProvider: ShelfDropProviding, @unchecked Sendable {
    let provider: NSItemProvider

    var carriesFileURL: Bool { provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }

    func loadFileURL(_ done: @escaping @Sendable (URL?) -> Void) {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            done(ShelfIslandDrop.fileURL(from: item))
        }
    }
}

@MainActor struct LiveShelfDropSink: ShelfDropSink {
    var acceptsDrops: Bool {
        AppFeature.shelf.isAvailable && PortHost.defaults.bool(forKey: DefaultsKey.shelfEnabled)
    }

    func add(_ urls: [URL]) -> Bool {
        ShelfLane.prepareStore()
        return ShelfService.shared.addFiles(urls)
    }
}

enum ShelfIslandDrop {
    static let acceptedTypes: [UTType] = [.fileURL]

    /// What `NSItemProvider.loadItem` returns for a file URL, as a file URL. Anything else is nil.
    static func fileURL(from item: NSSecureCoding?) -> URL? {
        let url: URL?
        switch item {
        case let data as Data: url = URL(dataRepresentation: data, relativeTo: nil)
        case let nsurl as NSURL: url = nsurl as URL
        default: url = nil
        }
        guard let url, url.isFileURL else { return nil }
        return url
    }

    /// Answers the drop at once (accepted or not) and adds the files when every provider has answered, in the order
    /// they were dragged. `completion` runs on the main actor with the number of files added (0 when none).
    @MainActor @discardableResult
    static func handle(_ providers: [any ShelfDropProviding], into sink: any ShelfDropSink,
                       completion: (@MainActor @Sendable (Int) -> Void)? = nil) -> Bool {
        guard sink.acceptsDrops else { return false }
        let matching = providers.filter { $0.carriesFileURL }
        guard !matching.isEmpty else { return false }
        let collector = Collector(count: matching.count)
        for (index, provider) in matching.enumerated() {
            provider.loadFileURL { url in
                guard let urls = collector.record(url, at: index) else { return }
                Task { @MainActor in
                    let added = !urls.isEmpty && sink.add(urls)
                    completion?(added ? urls.count : 0)
                }
            }
        }
        return true
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL?]
        private var pending: Int

        init(count: Int) {
            urls = Array(repeating: nil, count: count)
            pending = count
        }

        /// The URLs in provider order once the last provider has answered, nil before.
        func record(_ url: URL?, at index: Int) -> [URL]? {
            lock.lock()
            defer { lock.unlock() }
            urls[index] = url
            pending -= 1
            return pending == 0 ? urls.compactMap { $0 } : nil
        }
    }
}

// MARK: - Scratchpad lane

/// Binds the ported Scratchpad as a NEW registry feature, `scratchpad` (off until the person switches it on:
/// `PortFeatureBinding` never turns a ported feature on by itself). Start and stop are the service's own sync: the
/// shortcut and the floating pad appear only after the switch.
///
/// One writer for `Scratchpad.json`: our Clipboard module still has a Scratchpad pane that reads and writes that
/// file in its own codec until it is retired (it is not part of this lane's write surface). Both codecs read each
/// other's file (ours drops nothing it does not know, the ported one keeps up to 12 pads of 40 characters), and
/// `ScratchpadLegacyBackup` copies the file once before the ported store first rewrites it.
enum ScratchpadLane {
    struct Runtime {
        var backupLegacyFile: @MainActor () -> Void
        var sync: @MainActor () -> Void
        var stop: @MainActor () -> Void

        @MainActor private static var touched = false

        static let live = Runtime(
            backupLegacyFile: {
                if let directory = PrivateFileStore.containerURL { _ = ScratchpadLegacyBackup.run(directory: directory) }
            },
            sync: { touched = true; ScratchpadService.shared.syncWithPreferences() },
            stop: { if touched { ScratchpadService.shared.syncWithPreferences() } })
    }

    static let pageID = "scratchpad"

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        binding.bind(
            "scratchpad",
            page: PortFeaturePage(pageID: pageID) { AnyView(ScratchpadPage()) },
            start: {
                runtime.backupLegacyFile()
                runtime.sync()
            },
            stop: { runtime.stop() })
    }
}

/// Copies our Clipboard module's `Scratchpad.json` to `Scratchpad.pre-port.json` once, before the ported store can
/// rewrite it. The original stays; an existing backup is never replaced.
enum ScratchpadLegacyBackup {
    static let fileName = "Scratchpad.json"
    static let backupName = "Scratchpad.pre-port.json"

    enum Outcome: Equatable { case noFile, alreadyBackedUp, backedUp, failed }

    static func run(directory: URL, fileManager: FileManager = .default) -> Outcome {
        let source = directory.appendingPathComponent(fileName)
        let backup = directory.appendingPathComponent(backupName)
        guard fileManager.fileExists(atPath: source.path) else { return .noFile }
        guard !fileManager.fileExists(atPath: backup.path) else { return .alreadyBackedUp }
        guard let data = try? Data(contentsOf: source),
              PrivateFileStore.write(data, to: backup),
              (try? Data(contentsOf: backup)) == data else { return .failed }
        return .backedUp
    }
}

/// Settings page 12 (Brouillon): the rows of the ported Quick tools page that belong to the scratchpad.
private struct ScratchpadPage: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var scratchpad = ScratchpadService.shared
    @AppStorage(DefaultsKey.scratchpadShortcutEnabled) private var shortcutEnabled = false
    @AppStorage(DefaultsKey.scratchpadRetention) private var retention = ScratchpadRetention.never.rawValue
    @AppStorage(DefaultsKey.scratchpadCloseOnClickOutside) private var closeOnClickOutside = true
    @AppStorage(DefaultsKey.scratchpadBackgroundOpacity) private var backgroundOpacity = 0.0
    @AppStorage(DefaultsKey.scratchpadTextSize) private var textSize = ScratchpadSupport.defaultTextSize

    var body: some View {
        let text = FeatureStrings.scratchpad(l10n.language)
        Form {
            Section {
                Button {
                    ScratchpadService.shared.show()
                } label: {
                    Label(text.openButton, systemImage: "note.text")
                }
                Text(text.panelCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(text.retentionTitle, selection: $retention) {
                    Text(text.retentionNever).tag(ScratchpadRetention.never.rawValue)
                    Text(text.retentionDay).tag(ScratchpadRetention.day.rawValue)
                    Text(text.retentionWeek).tag(ScratchpadRetention.week.rawValue)
                    Text(text.retentionMonth).tag(ScratchpadRetention.month.rawValue)
                }
                Text(text.retentionCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(text.closeOnClickOutside, isOn: $closeOnClickOutside)
                    .onChange(of: closeOnClickOutside) { _, _ in
                        ScratchpadService.shared.outsideClickPreferenceDidChange()
                    }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(text.textSize)
                        Spacer()
                        Text("\(Int(ScratchpadSupport.sanitizedTextSize(textSize)))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: textSizeBinding, in: ScratchpadSupport.textSizeRange, step: 1)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(text.backgroundOpacity)
                    Slider(value: opacityBinding, in: ScratchpadSupport.backgroundOpacityRange, step: 0.05)
                    HStack {
                        Text(text.backgroundTranslucent)
                        Spacer()
                        Text(text.backgroundOpaque)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Toggle(l10n.s.quickToolShortcutToggle, isOn: $shortcutEnabled)
                    .onChange(of: shortcutEnabled) { _, _ in
                        ScratchpadService.shared.syncWithPreferences()
                    }
                ShortcutPreferenceRow(role: .scratchpad, isEnabled: shortcutEnabled) {
                    ScratchpadService.shared.syncWithPreferences()
                }
                if shortcutEnabled, scratchpad.shortcutRegistrationFailed {
                    Text(l10n.s.shortcutUnavailable)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text(text.pageTitle)
            }
        }
        .formStyle(.grouped)
    }

    private var opacityBinding: Binding<Double> {
        Binding(get: { ScratchpadSupport.sanitizedBackgroundOpacity(backgroundOpacity) },
                set: { backgroundOpacity = ScratchpadSupport.sanitizedBackgroundOpacity($0) })
    }

    private var textSizeBinding: Binding<Double> {
        Binding(get: { ScratchpadSupport.sanitizedTextSize(textSize) },
                set: { textSize = ScratchpadSupport.sanitizedTextSize($0) })
    }
}
