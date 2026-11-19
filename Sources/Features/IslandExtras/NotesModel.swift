import Foundation
import Observation

/// The text of the "Notes" tab. Every edit is saved at once (one short note, a few KB): there is no unsaved state to lose.
@MainActor @Observable
final class NotesModel {
    private let store: NotesStore
    private var loaded = false

    var text: String {
        didSet {
            guard loaded else { return }
            if text.count > NotesStore.maxLength { text = String(text.prefix(NotesStore.maxLength)); return }
            saveFailed = !store.save(text)
        }
    }
    private(set) var saveFailed = false

    init(store: NotesStore = NotesStore(directory: NotesStore.defaultDirectory)) {
        self.store = store
        text = store.load()
        loaded = true
    }

    var remaining: Int { NotesStore.maxLength - text.count }
}
