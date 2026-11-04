import Foundation

/// The only writer. One call at a time (each `setDefault` is awaited before the next starts), the journal written
/// before the first change, and nothing at all without the confirmation id of the preview on screen.
@MainActor
public final class DefaultAppsApplier {
    let launchServices: any LaunchServicesFacading
    let planner: ReplacementPlanner
    let journal: DefaultAppsJournalStore
    let choices: DefaultAppsChoicesStore
    let now: () -> Date
    let log: (String) -> Void
    /// Shared with the guard: one LaunchServices writer at a time.
    let gate: DefaultAppsWriteGate
    /// False once the feature is switched off (kill switch, safe mode): the loops write nothing more.
    let shouldContinue: @MainActor () -> Bool

    public init(launchServices: any LaunchServicesFacading, planner: ReplacementPlanner, journal: DefaultAppsJournalStore,
                choices: DefaultAppsChoicesStore, now: @escaping () -> Date = Date.init, log: @escaping (String) -> Void = { _ in },
                gate: DefaultAppsWriteGate = DefaultAppsWriteGate(), shouldContinue: @escaping @MainActor () -> Bool = { true }) {
        self.gate = gate
        self.shouldContinue = shouldContinue
        self.launchServices = launchServices
        self.planner = planner
        self.journal = journal
        self.choices = choices
        self.now = now
        self.log = log
    }

    // MARK: apply

    public func apply(_ preview: ReplacementPreview, confirmedPreviewID: UUID?) async -> ApplyReport {
        guard confirmedPreviewID == preview.id else {
            log("apply refused: preview not confirmed")
            return ApplyReport(outcomes: preview.items.map { outcome($0, .skipped("Non confirmé : rien n’a été modifié.")) },
                               stoppedEarly: false, notice: "Rien n’a été modifié : l’aperçu n’a pas été confirmé.")
        }
        // One writer at a time (the guard waits for this run, this run waits for a guard pass).
        await gate.acquire()
        defer { gate.release() }
        var outcomes: [ItemOutcome] = []
        var valid: [(item: PreviewItem, previous: String?)] = []
        // Checked again here, whatever the preview says: the policy is asked directly (a preview item's own flag is
        // never trusted), a protected item needs its explicit pick, the replacement must declare that it can open the
        // item, and the handler must still be the one the preview showed. The handler recorded for the undo is the
        // LIVE one read now, never the one of an older scan.
        for item in preview.items {
            let protected = ProtectionPolicy.isProtected(kind: item.kind, identifier: item.identifier)
            if protected && !item.explicitlyPicked {
                outcomes.append(outcome(item, .skipped(RefusalReason.protectedItem.text)))
            } else if !declared(preview.replacement, item) {
                outcomes.append(outcome(item, .skipped(RefusalReason.replacementCannotOpen.text)))
            } else {
                let liveNow = live(item.kind, item.identifier)
                if liveNow != item.previousBundleID {
                    outcomes.append(outcome(item, .skipped("A changé depuis l’aperçu : relancez l’aperçu.")))
                    log("skipped \(item.id): live handler \(liveNow ?? "none") differs from the preview")
                } else {
                    valid.append((item, liveNow))
                }
            }
        }
        guard !valid.isEmpty else { return ApplyReport(outcomes: outcomes, stoppedEarly: false, notice: "Rien à changer.") }

        let entry = JournalEntry(date: now(), replacementBundleID: preview.replacement.bundleID,
                                 replacementName: preview.replacement.name, sourceName: preview.sourceName,
                                 changes: valid.map { JournalChange(kind: $0.item.kind, identifier: $0.item.identifier, previousBundleID: $0.previous) })
        guard journal.append(entry) else {
            log("apply refused: journal not writable or full")
            return ApplyReport(outcomes: outcomes + valid.map { outcome($0.item, .skipped("Journal plein ou illisible : rien n’a été modifié.")) },
                               stoppedEarly: false, notice: "Le journal d’annulation ne peut pas recevoir ce changement en entier (plein ou illisible) : rien n’a été modifié.")
        }

        var breaker = RunBreaker()
        var timedOut = false
        for (item, _) in valid {
            if breaker.tripped || !shouldContinue() {
                outcomes.append(outcome(item, .skipped("Interrompu.")))
                if !breaker.tripped { breaker.stop() }
                continue
            }
            do {
                try await write(item, to: preview.replacement)
                let live = readBack(item)
                if live == preview.replacement.bundleID {
                    journal.mark(entry: entry.id, key: item.id, state: .applied)
                    choices.upsert(StoredChoice(kind: item.kind, identifier: item.identifier,
                                                bundleID: preview.replacement.bundleID,
                                                explicitlyPicked: item.explicitlyPicked && ProtectionPolicy.isProtected(kind: item.kind, identifier: item.identifier)))
                    outcomes.append(outcome(item, .success))
                    log("applied \(item.id) -> \(preview.replacement.bundleID)")
                } else {
                    journal.mark(entry: entry.id, key: item.id, state: .unverified)
                    outcomes.append(outcome(item, .unverified))
                    log("unverified \(item.id)")
                }
                breaker.recordSuccess()
            } catch {
                if (error as? LaunchServicesError)?.timedOut == true {
                    // Unknown, not failed: macOS may still answer. The change stays `planned` in the journal, and the
                    // undo only acts when the live handler is this replacement.
                    timedOut = true
                    outcomes.append(outcome(item, .unverified))
                    log("timeout \(item.id): outcome unknown, journal keeps it planned")
                } else {
                    journal.mark(entry: entry.id, key: item.id, state: .failed)
                    outcomes.append(outcome(item, .failure(message(error))))
                    log("failed \(item.id): \(message(error))")
                }
                breaker.record(error)
            }
        }
        return ApplyReport(outcomes: outcomes, stoppedEarly: breaker.tripped,
                           notice: timedOut ? "macOS n’a pas répondu à temps : le dernier réglage est incertain, le reste n’a pas été tenté. L’annulation vérifie la valeur réelle."
                               : breaker.tripped ? "Interrompu : les types restants n’ont pas été tentés." : nil)
    }

    // MARK: undo

    /// Puts back what `entries` changed, only where this feature's value is still the live one. Resolved items leave
    /// the journal; a failure stays so it can be tried again by hand.
    public func undo(entries: [JournalEntry], restoringOriginals: Bool = false) async -> ApplyReport {
        await gate.acquire()
        defer { gate.release() }
        let plan = UndoPlanner.plan(entries: entries, originals: restoringOriginals ? journal.originals : [:])
        guard !plan.isEmpty else { return ApplyReport(outcomes: [], stoppedEarly: false, notice: "Rien à annuler.") }
        var outcomes: [ItemOutcome] = []
        var breaker = RunBreaker()
        for item in plan {
            let label = title(for: item)
            func done(_ result: ItemResult) { outcomes.append(ItemOutcome(kind: item.kind, identifier: item.identifier, title: label, result: result)) }
            if breaker.tripped || !shouldContinue() {
                done(.skipped("Interrompu.")); if !breaker.tripped { breaker.stop() }; continue
            }
            guard live(item.kind, item.identifier) == item.expectedCurrent else {
                done(.skipped("Modifié depuis : laissé tel quel.")); continue
            }
            guard let previous = item.restoreTo else { done(.skipped("Ancien choix inconnu.")); continue }
            guard let url = launchServices.applicationURL(forBundleID: previous) else {
                done(.failure("L’application d’origine est introuvable.")); continue
            }
            // The guard must never see a choice for a type that is being given back: it goes first.
            choices.remove(keys: [item.id])
            do {
                switch item.kind {
                case .contentType: try await launchServices.setDefault(appURL: url, contentType: item.identifier)
                case .scheme: try await launchServices.setDefault(appURL: url, scheme: item.identifier)
                }
                done(live(item.kind, item.identifier) == previous ? .success : .unverified)
                breaker.recordSuccess()
                log("restored \(item.id) -> \(previous)")
            } catch {
                done(.failure(message(error)))
                log("restore failed \(item.id): \(message(error))")
                breaker.record(error)
            }
        }
        // An interrupted item was never tried: it stays in the journal like a failure (its undo record is not lost).
        let resolved = Set(outcomes.filter { !$0.result.isFailure && $0.result != .skipped("Interrompu.") }.map(\.key))
        let targeted = Set(entries.map(\.id))
        let remaining: [JournalEntry] = journal.entries.compactMap { entry in
            guard targeted.contains(entry.id) else { return entry }
            var entry = entry
            entry.changes.removeAll { resolved.contains($0.key) || $0.state == .failed }
            return entry.changes.isEmpty ? nil : entry
        }
        journal.replaceEntries(remaining)
        choices.remove(keys: resolved)
        return ApplyReport(outcomes: outcomes, stoppedEarly: breaker.tripped,
                           notice: breaker.tripped ? "Interrompu : le reste n’a pas été tenté." : nil)
    }

    // MARK: helpers

    private func write(_ item: PreviewItem, to app: AppProfile) async throws {
        switch item.kind {
        case .contentType: try await launchServices.setDefault(appURL: app.url, contentType: item.identifier)
        case .scheme: try await launchServices.setDefault(appURL: app.url, scheme: item.identifier)
        }
    }

    private func readBack(_ item: PreviewItem) -> String? { live(item.kind, item.identifier) }

    private func live(_ kind: ChangeKind, _ identifier: String) -> String? {
        switch kind {
        case .contentType: launchServices.defaultHandlerBundleID(forContentType: identifier)
        case .scheme: launchServices.defaultHandlerBundleID(forScheme: identifier)
        }
    }

    private func declared(_ app: AppProfile, _ item: PreviewItem) -> Bool {
        switch item.kind {
        case .contentType: planner.canOpen(app, contentType: item.identifier)
        case .scheme: planner.canOpen(app, scheme: item.identifier)
        }
    }

    private func outcome(_ item: PreviewItem, _ result: ItemResult) -> ItemOutcome {
        ItemOutcome(kind: item.kind, identifier: item.identifier, title: item.title, result: result)
    }

    private func title(for item: UndoItem) -> String {
        switch item.kind {
        case .contentType: planner.catalog.description(forIdentifier: item.identifier) ?? item.identifier
        case .scheme: "Liens \(item.identifier):"
        }
    }

    private func message(_ error: Error) -> String {
        (error as? LaunchServicesError)?.message ?? error.localizedDescription
    }
}
