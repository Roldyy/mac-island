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

    @ObservationIgnored private var importGeneration = 0
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

    /// Reads on a background thread, then shows the result on the main actor. A second pick while the first is
    /// still being read wins: the older result is dropped.
    func importFileInBackground(at url: URL) async {
        importGeneration += 1
        let generation = importGeneration
        let result = await Task.detached(priority: .userInitiated) {
            Result { try TerminalColorProfileParser.read(url: url) }
        }.value
        guard generation == importGeneration else { return }
        show(result)
    }

    /// Same as `importFileInBackground`, but reads on the calling thread (tests, scripts).
    func importFile(at url: URL) {
        importGeneration += 1
        show(Result { try TerminalColorProfileParser.read(url: url) })
    }

    private func show(_ result: Result<TerminalColorProfileImport, Error>) {
        errorMessage = nil
        statusMessage = nil
        switch result {
        case .success(let value):
            pending = value
        case .failure(let error):
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
        var savedImport = false
        switch change {
        case .imported(let profile):
            let id = library.add(profile)
            library.activate(id)
            name = "« \(library.profile(id: id)?.name ?? profile.name) »"
            savedImport = true
        case .existing(let id):
            guard let profile = library.profile(id: id) else { return }
            library.activate(id)
            name = "« \(profile.name) »"
        case .defaultTheme:
            library.activate(nil)
        }
        guard store.save(library) else {
            reload()  // the stored library is untouched: show it, do not restart on a profile that was not kept
            errorMessage = TerminalColorProfileError.cannotSave.errorDescription
            return
        }
        if savedImport { pending = nil }
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
        if !store.save(library) {
            reload()
            errorMessage = TerminalColorProfileError.cannotSave.errorDescription
        }
        renamingID = nil
    }

    func cancelRename() { renamingID = nil }

    /// Deleting never restarts the terminal: if the profile was active, the default theme returns at the next start.
    func delete(_ id: UUID) {
        let wasActive = library.activeID == id
        library.remove(id)
        if !store.save(library) {
            reload()
            errorMessage = TerminalColorProfileError.cannotSave.errorDescription
            return
        }
        if renamingID == id { renamingID = nil }
        statusMessage = wasActive ? "Profil supprimé. Le terminal retrouvera ses couleurs par défaut à son prochain démarrage." : nil
    }
}
