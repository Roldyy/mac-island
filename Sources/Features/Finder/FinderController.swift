import AppKit
import Foundation
import os

/// The outcome of the last action, as data (the view turns it into a line). Counts only, no names.
enum FinderOutcome: Equatable {
    case cutMarked(Int)
    case nothingSelected
    case moved(Int)
    case movedPartial(moved: Int, failed: Int)
    case moveFailed(Int)
    case imageSaved
    case imageFailed
    case refused(MoveRefusal)
    case automationDenied
    case scriptFailed
}

/// Cut / paste-move / paste-image logic with every side effect behind a protocol. Main actor.
@MainActor
final class FinderController {
    private let log = Logger(subsystem: "be.roldy.macisland", category: "finder")

    private let scripting: FinderScripting
    private let environment: FinderEnvironment
    private let pasteboard: PasteboardReading
    private let inspector: FileInspecting
    private let mover: FileMoving
    private let settings: () -> (cutPaste: Bool, image: Bool)
    private let clock: @Sendable () -> Date
    private let timeZone: () -> TimeZone

    /// What the tap thread reads. Kept in step with `cut`, the settings and the frontmost app.
    let keyState = FinderKeyState()
    private let evaluator: FinderKeyEvaluator
    private var activationObserver: NSObjectProtocol?

    private(set) var cut = PendingCut()
    private(set) var outcome: FinderOutcome?
    /// Set when a move was refused only for size: `confirmLargeMove()` runs it.
    private(set) var awaitingConfirmation: (items: [URL], destination: URL)?
    private var chain: Task<Void, Never>?
    var onChange: () -> Void = {}

    init(scripting: FinderScripting, environment: FinderEnvironment, pasteboard: PasteboardReading,
         inspector: FileInspecting = SystemFileInspector(), mover: FileMoving = FileManagerMover(),
         settings: @escaping () -> (cutPaste: Bool, image: Bool),
         clock: @escaping @Sendable () -> Date = { Date() }, timeZone: @escaping () -> TimeZone = { .current }) {
        self.scripting = scripting
        self.environment = environment
        self.pasteboard = pasteboard
        self.inspector = inspector
        self.mover = mover
        self.settings = settings
        self.clock = clock
        self.timeZone = timeZone
        self.evaluator = FinderKeyEvaluator(environment: environment, pasteboard: pasteboard,
                                            state: keyState, clock: clock)
    }

    var cutCount: Int { cut.count(now: clock(), pasteboardChangeCount: pasteboard.changeCount) }

    // MARK: Snapshot for the tap thread

    /// Copies the cut and the settings into the snapshot. Call after any change to either.
    func publish() {
        let s = settings()
        let expires = cut.expiresAt
        let count = cut.pasteboardChangeCount
        keyState.update {
            $0.cutExpiresAt = expires
            $0.cutPasteboardChangeCount = count
            $0.cutPasteEnabled = s.cutPaste
            $0.imagePasteEnabled = s.image
        }
    }

    func refreshFrontmost() {
        let front = environment.isFinderFrontmost()
        keyState.update { $0.finderFrontmost = front }
    }

    /// Starts following the frontmost app (the tap thread only reads the flag). Idempotent.
    func activate() {
        refreshFrontmost()
        publish()
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFrontmost() }
        }
    }

    func deactivate() {
        if let o = activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        activationObserver = nil
        keyState.update { $0.finderFrontmost = false }
    }

    // MARK: Decision (synchronous)

    /// Main-actor entry (tests, fallbacks): refreshes the snapshot from the environment, then decides.
    func decide(_ chord: KeyChord) -> KeyDecision {
        refreshFrontmost()
        publish()
        return evaluator.decide(chord)
    }

    /// The tap thread's entry: decision plus its immediate state change, no main-actor hop. Pair it with
    /// `perform` on the main actor.
    nonisolated func tapDecision(_ chord: KeyChord) -> KeyDecision { evaluator.decideApplying(chord) }

    /// Handles a key on the main actor: returns true to swallow it.
    func handleKey(_ chord: KeyChord) -> Bool {
        let d = decide(chord)
        keyState.update { $0.apply(d) }
        perform(d)
        return d.swallows
    }

    /// The side effect of a decision already applied to the snapshot.
    func perform(_ decision: KeyDecision) {
        switch decision {
        case .pass, .swallowRepeat:
            break
        case .passAndCancelCut:
            cancelCut()
        case .swallowCut:
            enqueue { await self.markCut() }
        case .swallowPasteMove:
            enqueue { await self.pasteMove() }
        case .swallowPasteImage:
            enqueue { await self.pasteImage() }
        }
    }

    func cancelCut() {
        cut.cancel()
        awaitingConfirmation = nil
        publish()
        onChange()
    }

    /// Lets tests (and `stop()`) wait for every queued action.
    func idle() async { await chain?.value }

    func confirmLargeMove() {
        guard let pending = awaitingConfirmation else { return }
        awaitingConfirmation = nil
        enqueue { await self.execute(items: pending.items, destination: pending.destination, confirmed: true) }
    }

    // MARK: Actions

    /// Actions run one after the other, so Cmd+X then Cmd+V typed fast stay in order.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = chain
        chain = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    private func markCut() async {
        defer {
            keyState.update { $0.inFlightCuts = max(0, $0.inFlightCuts - 1) }
            publish()
            onChange()
        }
        do {
            let items = try await scripting.selection()
            cut.mark(items, now: clock(), pasteboardChangeCount: pasteboard.changeCount)
            outcome = items.isEmpty ? .nothingSelected : .cutMarked(items.count)
            log.info("cut marked count=\(items.count, privacy: .public)")
        } catch {
            outcome = Self.outcome(for: error)
            log.error("selection failed")
        }
    }

    private func pasteMove() async {
        let items = cut.activeItems(now: clock(), pasteboardChangeCount: pasteboard.changeCount)
        guard !items.isEmpty else { return }
        guard finderOwnsKeyboard() else { return }
        do {
            let destination = try await scripting.targetFolder()
            // Finder took a moment to answer: the user may have switched app or cancelled the cut meanwhile.
            guard finderOwnsKeyboard(),
                  !cut.activeItems(now: clock(), pasteboardChangeCount: pasteboard.changeCount).isEmpty else { return }
            await execute(items: items, destination: destination, confirmed: false)
        } catch {
            outcome = Self.outcome(for: error)
            onChange()
        }
    }

    private func execute(items: [URL], destination: URL, confirmed: Bool) async {
        let inspector = self.inspector, mover = self.mover
        let result = await Task.detached { () -> Result<MoveReport, MoveRefusal> in
            switch MovePlanner.plan(items: items, destination: destination, inspector: inspector, confirmedLarge: confirmed) {
            case .failure(let refusal): return .failure(refusal)
            case .success(let plan): return .success(MoveExecutor.run(plan, inspector: inspector, mover: mover))
            }
        }.value
        switch result {
        case .failure(.needsConfirmation(let n)):
            awaitingConfirmation = (items, destination)
            outcome = .refused(.needsConfirmation(count: n))
            log.info("move needs confirmation count=\(n, privacy: .public)")
        case .failure(let refusal):
            outcome = .refused(refusal)
            if refusal == .sameFolder { cut.cancel(); publish() }
            log.info("move refused")
        case .success(let report):
            // Only failed sources that still exist stay cut, and they keep the first timer: a deleted
            // source would otherwise keep Cmd+V swallowed, and a retry loop would never expire.
            cut.retain(report.failedSources.filter(inspector.exists))
            publish()
            switch (report.moved, report.failed) {
            case (let m, 0): outcome = .moved(m)
            case (0, let f): outcome = .moveFailed(f)
            case (let m, let f): outcome = .movedPartial(moved: m, failed: f)
            }
            log.info("move done moved=\(report.moved, privacy: .public) failed=\(report.failed, privacy: .public)")
        }
        onChange()
    }

    private func pasteImage() async {
        guard finderOwnsKeyboard(), let png = pasteboard.pngData() else {
            outcome = .imageFailed; onChange(); return
        }
        do {
            let folder = try await scripting.targetFolder()
            guard finderOwnsKeyboard() else { outcome = .imageFailed; onChange(); return }
            try ImagePaste.save(png: png, in: folder, date: clock(), timeZone: timeZone(), inspector: inspector)
            outcome = .imageSaved
            log.info("image saved")
        } catch let error as FinderScriptError {
            outcome = Self.outcome(for: error)
        } catch let refusal as MoveRefusal {
            outcome = .refused(refusal)
        } catch {
            outcome = .imageFailed
        }
        onChange()
    }

    /// Frontmost AND focused in Finder, asked again at action time: the key was decided earlier.
    private func finderOwnsKeyboard() -> Bool {
        FinderFocus.ownsKeyboard(finderFrontmost: environment.isFinderFrontmost(),
                                 focusedAppPID: environment.focusedApplicationPID(), finderPID: environment.finderPID())
    }

    nonisolated static func outcome(for error: Error) -> FinderOutcome {
        (error as? FinderScriptError) == .notPermitted ? .automationDenied : .scriptFailed
    }
}
