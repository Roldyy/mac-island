// SPDX-License-Identifier: GPL-3.0-or-later
// Lane W7D (uninstaller). The lane owns this file.

import AppKit
import IslandUI
import SwiftUI

// MARK: - Lane

/// Binds the ported uninstaller (Settings page "uninstaller", the menu panel section, the command bar source): pick or
/// drop an app, see the files it left behind, move what is ticked to the Trash.
///
/// What this lane guarantees, each point pinned by a test:
/// - Trash only. The only removal call in `Services/Uninstall` is `FileManager.trashItem`: never `removeItem`, `rm`,
///   `unlink`, a shell or an AppleScript. An item the person cannot trash (a root-owned app, a protected folder) is
///   reported as failed and left in place: there is no Finder fallback, no administrator prompt (patch 1554).
/// - Never system paths. `UninstallPathPolicy` decides, lexically, at scan time and again at the moment of the
///   move, and the scan no longer walks `/Library`, the install receipts or `/Users/Shared` (patch 1555).
/// - Every path is shown first. `removeSelected()` only asks: the views show `UninstallReviewView` with the full
///   path and size of every row, and `confirmReview` is the one route to `performRemoval` (patch 1556).
///
/// Start does nothing (the feature is a page the person opens); stop (switch off, kill switch, safe mode,
/// quarantine) closes a flow that is not removing and drops a plan awaiting review. A move already started finishes:
/// each item is one reversible Trash move.
enum UninstallerLane {
    /// What the lane does to the upstream service. The registry tests swap it for a fake.
    struct Runtime {
        var start: @MainActor () -> Void
        var stop: @MainActor () -> Void

        @MainActor private static var touched = false

        static let live = Runtime(
            start: { touched = true },
            stop: { if touched { AppUninstaller.shared.reset() } })
    }

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        binding.bind("uninstaller",
                     page: PortFeaturePage(pageID: "uninstaller") { AnyView(UninstallerView()) },
                     start: { runtime.start() },
                     stop: { runtime.stop() })
    }
}

// MARK: - Which paths may ever be removed

/// The rule for what an uninstall may move to the Trash. Pure and lexical (no file access), so a test lists the
/// cases. A path is removable only when it is:
/// - the app bundle itself: a `.app` anywhere outside the system roots, or
/// - strictly below the person's home folder or the per-user cache and temp folders (`userRoots`), and not inside
///   a protected folder (Desktop, Documents, Downloads, Pictures..., keychains, mail, iCloud) and not one of the
///   shared containers themselves (`~/Library`, `~/Library/Caches`, `~/Library/Application Support`...).
/// Everything else (`/System`, `/Library`, `/usr`, `/private`, `/Users/Shared`, a volume root, `..` tricks, a
/// relative path) is refused: a non-bundle item outside the user roots never passes.
enum UninstallPathPolicy {
    /// Never removable, whatever the item is, and never where an app bundle may be removed from.
    static let systemRoots = [
        "/System", "/usr", "/bin", "/sbin", "/etc", "/var", "/private", "/Library", "/cores", "/dev", "/opt",
        "/Network",
    ]

    /// Folders of the home folder nothing inside may be removed from (relative to home).
    static let protectedTrees = [
        "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", ".Trash", ".ssh", ".gnupg",
        "Library/Keychains", "Library/Mail", "Library/Messages", "Library/Mobile Documents",
        "Library/CloudStorage", "Library/Photos", "Library/Safari",
    ]

    /// Folders that are the shared containers themselves: the folder is never removed, only what is in it
    /// (relative to home). The home folder itself is covered by "strictly below".
    static let protectedFolders = [
        "Applications", "Library", "Library/Application Support", "Library/Caches", "Library/Preferences",
        "Library/Containers", "Library/Group Containers", "Library/Logs", "Library/Saved Application State",
        "Library/LaunchAgents", "Library/WebKit", "Library/HTTPStorages", "Library/Application Scripts",
        "Library/Cookies", "Library/Internet Plug-Ins", "Library/PreferencePanes", "Library/Services",
        "Library/Fonts", "Library/Colors", "Library/Sounds", "Library/Screen Savers",
        ".config", ".cache", ".local", ".local/share",
    ]

    static func userRoots(home: String, darwinCache: String?, darwinTemp: String?) -> [String] {
        ([home] + [darwinCache, darwinTemp].compactMap { $0 }).map(normalized)
    }

    static func isRemovable(_ path: String, isAppBundle: Bool, userRoots: [String]) -> Bool {
        guard let clean = cleaned(path) else { return false }
        if isAppBundle {
            guard clean.hasSuffix(".app"), clean.split(separator: "/").count >= 2 else { return false }
            return !isInside(clean, roots: systemRoots)
        }
        for root in userRoots where clean.hasPrefix(root + "/") {
            let relative = String(clean.dropFirst(root.count + 1))
            guard !relative.isEmpty else { return false }
            // The protected lists are the home folder's; the per-user cache folders have no such subfolders.
            if protectedFolders.contains(relative) { return false }
            if protectedTrees.contains(where: { relative == $0 || relative.hasPrefix($0 + "/") }) { return false }
            return true
        }
        return false
    }

    /// Why a path is refused, in plain French, for the review and the failure note. Nil when it is allowed.
    static func refusalReason(_ path: String, isAppBundle: Bool, userRoots: [String]) -> String? {
        guard !isRemovable(path, isAppBundle: isAppBundle, userRoots: userRoots) else { return nil }
        guard let clean = cleaned(path) else { return "Chemin invalide." }
        if isInside(clean, roots: systemRoots) { return "Dossier système : jamais touché." }
        return "Hors de votre espace personnel : jamais touché."
    }

    /// Absolute, no NUL, no `..` component, no `.` component; repeated slashes and a trailing slash removed.
    static func cleaned(_ path: String) -> String? {
        guard path.hasPrefix("/"), !path.contains("\0") else { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !parts.contains(".."), !parts.contains(".") else { return nil }
        return "/" + parts.joined(separator: "/")
    }

    private static func normalized(_ path: String) -> String { cleaned(path) ?? path }

    private static func isInside(_ path: String, roots: [String]) -> Bool {
        roots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}

// MARK: - Review before anything moves

/// What the person is shown before the Trash moves: the app, every path with its size.
struct UninstallReviewPlan: Identifiable, Equatable {
    struct Row: Identifiable, Equatable {
        let id: UUID
        let path: String
        let size: Int64
        let isAppBundle: Bool
    }

    let id: UUID
    let appName: String
    let rows: [Row]

    init(id: UUID = UUID(), appName: String, rows: [Row]) {
        self.id = id
        self.appName = appName
        self.rows = rows
    }

    var totalSize: Int64 { rows.reduce(0) { $0 + $1.size } }

    func matches(selection ids: Set<UUID>) -> Bool { Set(rows.map(\.id)) == ids }
}

/// The two-step gate in front of the removal: `request` shows a plan, `confirm` lets the removal run only for
/// THAT plan and only while the selection is still exactly its rows. Any answer clears the plan.
struct UninstallReviewGate: Equatable {
    private(set) var pending: UninstallReviewPlan?

    mutating func request(_ plan: UninstallReviewPlan) { pending = plan }

    mutating func cancel() { pending = nil }

    mutating func confirm(_ plan: UninstallReviewPlan, currentSelection: Set<UUID>) -> Bool {
        defer { pending = nil }
        guard let pending, pending == plan, plan.matches(selection: currentSelection) else { return false }
        return true
    }
}

// MARK: - Texts

enum UninstallReviewText {
    static let title = "Vérifier avant de mettre à la corbeille"
    static let trashOnly = "Tout va dans la corbeille : rien n’est supprimé définitivement, vous pouvez le remettre en place."
    static let systemNote = "Les dossiers système (/Library, /System, reçus d’installation) ne sont jamais touchés."
    static let cancel = "Annuler"
    static let confirm = "Mettre à la corbeille"
    static let appBadge = "App"

    static func summary(app: String, count: Int, size: String) -> String {
        count == 1 ? "« \(app) » : 1 élément, \(size)." : "« \(app) » : \(count) éléments, \(size)."
    }
}

// MARK: - Views

/// Covers the uninstaller page while a plan awaits review: every full path and size, then two buttons.
struct UninstallReviewView: View {
    let plan: UninstallReviewPlan
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(UninstallReviewText.title, systemImage: "trash")
                .font(.headline)
            Text(UninstallReviewText.summary(app: plan.appName, count: plan.rows.count,
                                             size: ByteCountFormatter.string(fromByteCount: plan.totalSize, countStyle: .file)))
                .font(.callout)
            Text(UninstallReviewText.trashOnly)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(plan.rows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if row.isAppBundle {
                                Text(UninstallReviewText.appBadge)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.quaternary, in: Capsule())
                            }
                            Text(row.path)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Text(ByteCountFormatter.string(fromByteCount: row.size, countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            Text(UninstallReviewText.systemNote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            HStack {
                Button(UninstallReviewText.cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(UninstallReviewText.confirm, role: .destructive, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .islandGlass(cornerRadius: IslandRadius.large)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

private struct UninstallReviewOverlay: ViewModifier {
    @ObservedObject var uninstaller: AppUninstaller

    func body(content: Content) -> some View {
        content
            .overlay {
                if let plan = uninstaller.pendingReview {
                    UninstallReviewView(plan: plan,
                                        onCancel: { uninstaller.cancelReview() },
                                        onConfirm: { uninstaller.confirmReview(plan) })
                }
            }
            .onDisappear { uninstaller.cancelReview() }
    }
}

extension View {
    /// Shows the review of what the uninstaller is about to move, over this view.
    func uninstallReview(_ uninstaller: AppUninstaller) -> some View {
        modifier(UninstallReviewOverlay(uninstaller: uninstaller))
    }
}
