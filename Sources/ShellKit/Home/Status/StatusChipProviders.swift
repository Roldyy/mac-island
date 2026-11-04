import Foundation

/// The chips ShellKit can feed on its own (no PortKit, no feature module): network, load and disk.
/// `openMonitor` is the tap action of all three (nil leaves them without one); `temperature` is the optional
/// reading another lane supplies for the "Charge" chip.
///
/// The Network chip gets the live Wi-Fi name (CoreWLAN + Location) unless `nameProvider` says otherwise; a test
/// passes its own provider, or `liveWiFiName: false` for none. Building the live one asks for nothing: the Location
/// prompt appears once, when the chip first runs on Wi-Fi.
enum StatusChipProviders {
    @MainActor
    static func builtin(openMonitor: (@MainActor () -> Void)?,
                        temperature: (@MainActor () -> Double?)?,
                        temperatureStop: (@MainActor () -> Void)? = nil,
                        nameProvider: WiFiNameProvider? = nil,
                        liveWiFiName: Bool = true) -> [any StatusChipSource] {
        let names = nameProvider ?? (liveWiFiName ? WiFiNameProvider(reader: LiveSSIDReader()) : nil)
        return [
            NetworkChipSource(openMonitor: openMonitor, nameProvider: names),
            LoadChipSource(temperatureProvider: temperature, temperatureStop: temperatureStop, openMonitor: openMonitor),
            DiskChipSource(openMonitor: openMonitor),
        ]
    }
}
