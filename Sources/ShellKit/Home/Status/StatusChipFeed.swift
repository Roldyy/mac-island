import Foundation
import Observation

/// The live list of chips of the open island: the sources, the user's layout and the master switch in, the ordered
/// readings out.
///
/// The feed has no timer of its own. `start()` and `stop()` (called by the home while the island is open) fan out to
/// the sources, and only to those whose chip is enabled: a chip the user switched off costs nothing. Readings are
/// rebuilt when a source says it changed, or when the layout or the switch changes.
@MainActor @Observable
public final class StatusChipFeed {
    /// Readings of the enabled chips, in layout order. Empty while the island is closed.
    public private(set) var readings: [StatusChipReading] = []

    /// One source per kind (a later registration of a kind replaces the earlier one).
    public private(set) var sources: [any StatusChipSource] = []

    /// Which chips, in which order.
    public var layout: StatusChipLayout {
        didSet { if layout != oldValue { refresh() } }
    }

    /// The master switch ("Pastilles d'état").
    public var isEnabled: Bool {
        didSet { if isEnabled != oldValue { refresh() } }
    }

    @ObservationIgnored private var wantsRunning = false
    @ObservationIgnored private var running: Set<ObjectIdentifier> = []

    public init(sources: [any StatusChipSource] = [], layout: StatusChipLayout = .initial, isEnabled: Bool = true) {
        self.layout = layout
        self.isEnabled = isEnabled
        setSources(sources)
    }

    /// True while the home must keep room for the row: the switch is on and at least one enabled chip has a source.
    /// It does not depend on the readings, so the panel does not resize when the first value arrives.
    public var hasSlot: Bool { isEnabled && sources.contains { layout.contains($0.kind) } }

    /// Kinds that have a source in this build (the Settings page greys out the others).
    public var availableKinds: Set<StatusChipKind> { Set(sources.map(\.kind)) }

    public var isRunning: Bool { wantsRunning }

    /// Replaces the sources. The old ones are stopped; the new ones start at once when the feed is running.
    public func setSources(_ newSources: [any StatusChipSource]) {
        for source in sources where running.contains(ObjectIdentifier(source)) { source.stop() }
        running = []
        var byKind: [StatusChipKind: any StatusChipSource] = [:]
        for source in newSources { byKind[source.kind] = source }
        sources = StatusChipKind.allCases.compactMap { byKind[$0] }
        for source in sources { source.onChange = { [weak self] in self?.rebuild() } }
        refresh()
    }

    /// The island opened: start every source whose chip is enabled. Idempotent.
    public func start() {
        wantsRunning = true
        refresh()
    }

    /// The island closed: stop every source and drop the readings. Idempotent.
    public func stop() {
        wantsRunning = false
        refresh()
    }

    private func refresh() {
        reconcile()
        rebuild()
    }

    /// Starts the sources that should run and stops those that should not, each exactly once.
    private func reconcile() {
        for source in sources {
            let id = ObjectIdentifier(source)
            let shouldRun = wantsRunning && isEnabled && layout.contains(source.kind)
            if shouldRun {
                if running.insert(id).inserted { source.start() }
            } else if running.remove(id) != nil {
                source.stop()
            }
        }
    }

    private func rebuild() {
        var next: [StatusChipReading] = []
        if wantsRunning, isEnabled {
            let byKind = Dictionary(sources.map { ($0.kind, $0) }, uniquingKeysWith: { _, last in last })
            next = layout.kinds.compactMap { byKind[$0]?.reading }
        }
        if next != readings { readings = next }
    }
}
