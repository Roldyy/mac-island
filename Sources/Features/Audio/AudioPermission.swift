import Foundation

/// Audio capture (TCC kTCCServiceAudioCapture) status, as far as it can be known.
/// There is no public API to read it without trying; the only evidence is a probe tap.
enum AudioPermission: Equatable {
    /// No `NSAudioCaptureUsageDescription` in the running bundle: the system cannot prompt.
    case needsBundledApp
    case notChecked
    case ready
    case failed(Int32)

    static func resolve(hasUsageDescription: Bool, probe: Int32?) -> AudioPermission {
        guard hasUsageDescription else { return .needsBundledApp }
        guard let probe else { return .notChecked }
        return probe == 0 ? .ready : .failed(probe)
    }

    var line: String {
        switch self {
        case .needsBundledApp:
            return "Volume par app : disponible seulement dans l'app empaquetée et signée (pas avec swift run)."
        case .notChecked:
            return "Volume par app : autorisation de capture audio non demandée."
        case .ready:
            return "Volume par app : actif."
        case .failed(let status):
            return "Volume par app : capture audio refusée ou indisponible (code \(status))."
        }
    }

    var canRequest: Bool {
        switch self {
        case .notChecked, .failed: return true
        case .needsBundledApp, .ready: return false
        }
    }
}
