import Foundation

public enum GuardAction: Equatable, Sendable {
    case reapplied(String)
    case failed(String)
    case rateLimited(String)
    case skipped(String)
}

/// "Garder mes choix": re-applies the stored choices that macOS or an app update reset. Opt-in. A type is tried at
/// most once per `minimumInterval` (the attempt time is written before the call, so a failure counts too), calls
/// are serialised, and a run in progress is never doubled.
@MainActor
public final class DefaultAppsGuard {
    /// Never more than once per hour per type.
    public static let minimumInterval: TimeInterval = 3600
    /// Two checks closer than this are one (an app switching storm).
    public static let debounce: TimeInterval = 30

    let settings: DefaultAppsSettings
    let choices: DefaultAppsChoicesStore
    let launchServices: any LaunchServicesFacading
    let now: () -> Date
    let log: (String) -> Void
    /// Shared with apply and undo: one LaunchServices writer at a time.
    let gate: DefaultAppsWriteGate
    /// False while the feature is off (kill switch, safe mode) or an apply / undo owns the writes.
    let allowed: @MainActor () -> Bool
    private var running = false
    private var lastCheck: Date?

    public init(settings: DefaultAppsSettings, choices: DefaultAppsChoicesStore, launchServices: any LaunchServicesFacading,
                now: @escaping () -> Date = Date.init, log: @escaping (String) -> Void = { _ in },
                gate: DefaultAppsWriteGate = DefaultAppsWriteGate(), allowed: @escaping @MainActor () -> Bool = { true }) {
        self.gate = gate
        self.allowed = allowed
        self.settings = settings
        self.choices = choices
        self.launchServices = launchServices
        self.now = now
        self.log = log
    }

    /// One pass over the stored choices. `reason` goes to the log ("launch", "activation").
    @discardableResult
    public func check(reason: String) async -> [GuardAction] {
        guard settings.guardEnabled, allowed(), !running else { return [] }
        let started = now()
        if let last = lastCheck, started.timeIntervalSince(last) < Self.debounce { return [] }
        lastCheck = started
        running = true
        defer { running = false }
        // Waits for a running apply or undo, and re-checks everything once it has the turn: the stored choices are
        // read only now, so a choice the undo just removed is never re-applied.
        await gate.acquire()
        defer { gate.release() }
        guard settings.guardEnabled, allowed(), !Task.isCancelled else { return [] }

        var actions: [GuardAction] = []
        var breaker = RunBreaker()
        for choice in choices.choices {
            let key = choice.key
            guard settings.guardEnabled, allowed(), !Task.isCancelled else { break }
            let current = live(choice)
            if current == choice.bundleID { continue }
            if ProtectionPolicy.isProtected(kind: choice.kind, identifier: choice.identifier) && !choice.explicitlyPicked {
                actions.append(.skipped(key)); continue
            }
            if breaker.tripped { actions.append(.skipped(key)); continue }
            if let last = choices.lastAttempt(for: key), now().timeIntervalSince(last) < Self.minimumInterval {
                actions.append(.rateLimited(key)); continue
            }
            guard let url = launchServices.applicationURL(forBundleID: choice.bundleID) else {
                actions.append(.skipped(key)); log("guard(\(reason)): \(key) skipped, app \(choice.bundleID) not found"); continue
            }
            choices.noteAttempt(for: key, at: now())
            do {
                switch choice.kind {
                case .contentType: try await launchServices.setDefault(appURL: url, contentType: choice.identifier)
                case .scheme: try await launchServices.setDefault(appURL: url, scheme: choice.identifier)
                }
                actions.append(.reapplied(key))
                breaker.recordSuccess()
                log("guard(\(reason)): re-applied \(key) -> \(choice.bundleID), macOS had \(current ?? "none")")
            } catch {
                actions.append(.failed(key))
                breaker.record(error)
                log("guard(\(reason)): \(key) failed: \((error as? LaunchServicesError)?.message ?? error.localizedDescription)")
            }
        }
        return actions
    }

    private func live(_ choice: StoredChoice) -> String? {
        switch choice.kind {
        case .contentType: launchServices.defaultHandlerBundleID(forContentType: choice.identifier)
        case .scheme: launchServices.defaultHandlerBundleID(forScheme: choice.identifier)
        }
    }
}
