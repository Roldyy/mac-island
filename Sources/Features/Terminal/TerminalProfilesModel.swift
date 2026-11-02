import Foundation
import Observation

/// What the user asked to wear, waiting for the restart decision.
enum TerminalProfileChange: Equatable {
    case imported(TerminalColorProfile)
    case existing(UUID)
    case defaultTheme
}

/// A restart that needs the user's word: a program other than the shell is running.
struct TerminalRestartConfirmation: Equatable {
    var change: TerminalProfileChange
    var process: String
}

/// The state behind the "Profil de couleurs" card: import, preview, apply (with restart), reset, list.
/// Nothing is written until the user applies; the terminal is never restarted without that click, and a running
/// program is never ended without a second one.
@MainActor
@Observable
final class TerminalProfilesModel {
    private(set) var library: TerminalProfileLibrary
    private(set) var pending: TerminalColorProfileImport?
    private(set) var confirmation: TerminalRestartConfirmation?
    private(set) var errorMessage: String?
    private(set) var statusMessage: String?
    var renamingID: UUID?
    var renameText = ""

    @ObservationIgnored private let store: TerminalProfileStore
    @ObservationIgnored private let session: TerminalRestarting

    init(store: TerminalProfileStore, session: TerminalRestarting) {
        self.store = store
        self.session = session
        library = store.load()
    }

    var activeName: String { library.active?.name ?? "Par défaut" }

    func reload() { library = store.load() }

    // MARK: Import

    func importFile(at url: URL) {
        errorMessage = nil
        statusMessage = nil
        do {
            pending = try TerminalColorProfileParser.read(url: url)
        } catch {
            pending = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? TerminalColorProfileError.unreadable.errorDescription
        }
    }

    func discardPending() {
        pending = nil
        errorMessage = nil
    }

    // MARK: Apply

    func applyPending() {
        guard let pending else { return }
        request(.imported(pending.profile))
    }

    func apply(_ id: UUID) { request(.existing(id)) }

    func resetToDefault() { request(.defaultTheme) }

    func confirmRestart() {
        guard let confirmation else { return }
        self.confirmation = nil
        perform(confirmation.change, restart: true)
    }

    func cancelRestart() {
        confirmation = nil
        statusMessage = "Redémarrage annulé : le terminal garde ses couleurs."
    }

    private func request(_ change: TerminalProfileChange) {
        errorMessage = nil
        statusMessage = nil
        switch session.restartDecision() {
        case .confirm(let process): confirmation = TerminalRestartConfirmation(change: change, process: process)
        case .restart: perform(change, restart: true)
        case .colorsOnNextStart: perform(change, restart: false)
        }
    }

    private func perform(_ change: TerminalProfileChange, restart: Bool) {
        reload()
        var name = "le profil par défaut"
        switch change {
        case .imported(let profile):
            let id = library.add(profile)
            library.activate(id)
            name = "« \(library.profile(id: id)?.name ?? profile.name) »"
            pending = nil
        case .existing(let id):
            guard let profile = library.profile(id: id) else { return }
            library.activate(id)
            name = "« \(profile.name) »"
        case .defaultTheme:
            library.activate(nil)
        }
        store.save(library)
        if restart {
            session.restartWithActiveProfile()
            statusMessage = "Terminal redémarré avec \(name)."
        } else {
            statusMessage = "Enregistré : \(name) s’appliquera au prochain démarrage du terminal."
        }
    }

    // MARK: List

    func beginRename(_ id: UUID) {
        renamingID = id
        renameText = library.profile(id: id)?.name ?? ""
    }

    func commitRename() {
        guard let id = renamingID else { return }
        library.rename(id, to: renameText)
        store.save(library)
        renamingID = nil
    }

    func cancelRename() { renamingID = nil }

    /// Deleting never restarts the terminal: if the profile was active, the default theme returns at the next start.
    func delete(_ id: UUID) {
        let wasActive = library.activeID == id
        library.remove(id)
        store.save(library)
        if renamingID == id { renamingID = nil }
        statusMessage = wasActive ? "Profil supprimé. Le terminal retrouvera ses couleurs par défaut à son prochain démarrage." : nil
    }
}
