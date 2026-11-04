import Foundation

/// The chips ShellKit can feed on its own (no PortKit, no feature module): network, load and disk.
/// `openMonitor` is the tap action of all three (nil leaves them without one); `temperature` is the optional
/// reading another lane supplies for the "Charge" chip.
enum StatusChipProviders {
    @MainActor
    static func builtin(openMonitor: (@MainActor () -> Void)?,
                        temperature: (@MainActor () -> Double?)?) -> [any StatusChipSource] {
        [
            NetworkChipSource(openMonitor: openMonitor),
            LoadChipSource(temperatureProvider: temperature, openMonitor: openMonitor),
            DiskChipSource(openMonitor: openMonitor),
        ]
    }
}
