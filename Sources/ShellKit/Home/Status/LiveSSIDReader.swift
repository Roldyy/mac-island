import CoreLocation
import CoreWLAN
import Foundation

/// The live door: CoreWLAN gives the name, CoreLocation owns the permission (macOS hides the SSID until the app may
/// use Location). The manager is created on first use, so nothing here runs, and no prompt can appear, before the
/// Network chip is resolved on Wi-Fi.
@MainActor
public final class LiveSSIDReader: NSObject, SSIDReading, @preconcurrency CLLocationManagerDelegate {
    public var onAuthorizationChange: (@MainActor () -> Void)?
    private var manager: CLLocationManager?

    public override init() { super.init() }

    private func locationManager() -> CLLocationManager {
        if let manager { return manager }
        let created = CLLocationManager()
        created.delegate = self
        manager = created
        return created
    }

    public var authorization: LocationAuthorization {
        let manager = locationManager()
        guard CLLocationManager.locationServicesEnabled() else { return .denied }
        switch manager.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        default: return .denied
        }
    }

    public func readSSID() -> String? { CWWiFiClient.shared().interface()?.ssid() }

    public func requestAuthorization() { locationManager().requestWhenInUseAuthorization() }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorizationChange?()
    }
}
