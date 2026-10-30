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
    private let clock: () -> Date
    private let timeZone: () -> TimeZone

    private(set) var cut = PendingCut()
    private(set) var outcome: FinderOutcome?
    /// Set when a move was refused only for size: `confirmLargeMove()` runs it.
    private(set) var awaitingConfirmation: (items: [URL], destination: URL)?
    private var inFlightCuts = 0
    private var chain: Task<Void, Never>?
    var onChange: () -> Void = {}

    init(scripting: FinderScripting, environment: FinderEnvironment, pasteboard: PasteboardReading,
         inspector: FileInspecting = SystemFileInspector(), mover: FileMoving = FileManagerMover(),
         settings: @escaping () -> (cutPaste: Bool, image: Bool),
         clock: @escaping () -> Date = Date.init, timeZone: @escaping () -> TimeZone = { .current }) {
        self.scripting = scripting
        self.environment = environment
        self.pasteboard = pasteboard
        self.inspector = inspector
        self.mover = mover
        self.settings = settings
        self.clock = clock
        self.timeZone = timeZone
    }

    var cutCount: Int { cut.count(now: clock()) }

    // MARK: Decision (synchronous, called from the tap)

    func decide(_ chord: KeyChord) -> KeyDecision {
        guard KeyDecision.isCandidate(chord), environment.isFinderFrontmost() else { return .pass }
        // The Accessibility query is the slow part: x and v always need it, c and Esc only with a cut pending.
        let isKeyOfCut = chord.keyCode == KeyCode.x || chord.keyCode == KeyCode.v
        let wantsEditingCheck = isKeyOfCut || cut.isActive(now: clock())
        let s = settings()
        let isPaste = chord.keyCode == KeyCode.v
        let ctx = FinderKeyContext(
            finderFrontmost: true,
            textEditing: wantsEditingCheck ? environment.isTextEditing() : false,
            hasPendingCut: cut.isActive(now: clock()) || inFlightCuts > 0,
            pasteboardHasFileURLs: isPaste ? pasteboard.hasFileURLs : false,
            pasteboardHasImage: isPaste ? pasteboard.hasImage : false,
            cutPasteEnabled: s.cutPaste, imagePasteEnabled: s.image)
        return KeyDecision.decide(chord, ctx)
    }

    /// Handles a key from the tap: returns true to swallow it.
    func handleKey(_ chord: KeyChord) -> Bool {
        let d = decide(chord)
        perform(d)
        return d.swallows
    }

    func perform(_ decision: KeyDecision) {
        switch decision {
        case .pass, .swallowRepeat:
            break
        case .passAndCancelCut:
            cancelCut()
        case .swallowCut:
            inFlightCuts += 1
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
        defer { inFlightCuts -= 1; onChange() }
        do {
            let items = try await scripting.selection()
            cut.mark(items, now: clock())
            outcome = items.isEmpty ? .nothingSelected : .cutMarked(items.count)
            log.info("cut marked count=\(items.count, privacy: .public)")
        } catch {
            outcome = Self.outcome(for: error)
            log.error("selection failed")
        }
    }

    private func pasteMove() async {
        let items = cut.activeItems(now: clock())
        guard !items.isEmpty else { return }
        guard environment.isFinderFrontmost() else { return }
        do {
            let destination = try await scripting.targetFolder()
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
            if refusal == .sameFolder { cut.cancel() }
            log.info("move refused")
        case .success(let report):
            let remaining = report.failedSources
            if remaining.isEmpty { cut.cancel() } else { cut.mark(remaining, now: clock()) }
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
        guard environment.isFinderFrontmost(), let png = pasteboard.pngData() else {
            outcome = .imageFailed; onChange(); return
        }
        do {
            let folder = try await scripting.targetFolder()
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

    nonisolated static func outcome(for error: Error) -> FinderOutcome {
        (error as? FinderScriptError) == .notPermitted ? .automationDenied : .scriptFailed
    }
}
