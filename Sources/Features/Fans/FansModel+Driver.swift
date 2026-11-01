import FanShared
import Foundation

/// The Fans model as the ported fan policy's driver. Every command goes through the model's own client, so the
/// heartbeat, the epoch that drops a late reply, the helper's rate limit and its thermal override all stay the
/// ones the Ventilos tab already uses. Nothing here talks to the SMC for writing and nothing registers the helper
/// except `installHelper()`, which the settings page calls from an explicit click.
extension FansModel: FanDriving {
    var access: FanDriverAccess {
        switch installStatus {
        case .notRegistered: .notRegistered
        case .requiresApproval: .requiresApproval
        case .enabled: .enabled
        case .notFound: .notFound
        }
    }

    var isReachable: Bool { helperReachable }
    var isManualActive: Bool { manualActive }

    func refreshAccess() { refreshInstallStatus() }

    func connectIfApproved() async { await appeared() }

    func openApprovalSettings() { openLoginItems() }

    func readFans() async -> [FanDriverFan]? {
        let source = self.source
        let result = await Task.detached(priority: .utility) { Result { try source.readFans() } }.value
        guard case .success(let fans) = result else { return nil }
        return fans.map {
            FanDriverFan(index: $0.index, actualRPM: $0.actualRPM, minRPM: $0.minRPM, maxRPM: $0.maxRPM,
                         targetRPM: $0.targetRPM, isManual: $0.mode == .manual)
        }
    }

    func setTarget(fan: Int, rpm: Double) async -> FanDriverOutcome {
        guard manualAvailable, rpm.isFinite, rpm > 0 else { return .unreachable }
        let epoch = automaticEpoch
        let result: FanCommandResult
        do {
            result = try await client.perform(.setTarget(fan: fan, rpm: rpm.rounded()))
        } catch {
            return .unreachable
        }
        // An explicit way back to automatic went out while this request was in flight: it wins.
        guard epoch == automaticEpoch else { return .automatic }
        handle(result)
        return Self.outcome(of: result)
    }

    func returnAllToAutomatic() async -> FanDriverOutcome { await returnToAutomatic() }

    func returnAllToAutomaticNow() {
        automaticEpoch += 1
        client.sendAllAutomaticBlocking(timeout: 0.5)
        stopManualAfterBlockingRestore()
    }

    static func outcome(of result: FanCommandResult) -> FanDriverOutcome {
        switch result.status {
        case .applied:
            if let fan = result.fan, let rpm = result.appliedRPM { return .applied(fan: fan, rpm: rpm) }
            return .failed(reason: "invalidReply")
        case .automatic: return .automatic
        case .forcedAutomatic: return .forcedAutomatic
        case .rejected: return .rejected(reason: result.reason)
        case .failed: return .failed(reason: result.reason)
        }
    }
}
