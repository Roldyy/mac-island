import FanShared
import Foundation

/// `FanHelper --self-test-read-only`: prints the JSON `FanSelfTestReport` and exits.
/// Reads only: this path creates an `AppleSMCReadOnlyClient` and never an `AppleSMCWriter`.
enum HelperSelfTestCommand {
    static func run() -> Int32 {
        do {
            let reader = try AppleSMCReadOnlyClient()
            let policy = FanSafetyPolicy()
            let sensors = TemperatureSensors(keys: TemperatureSensors.discover(reader.allKeys(),
                                                                               prefixes: TemperatureSensors.defaultPrefixes))
            let thermal = ThermalSnapshot(maxCelsius: sensors.maxCelsius(reader, plausible: policy.plausibleCelsius),
                                          pressure: ThermalPressure(ProcessInfo.processInfo.thermalState))
            let report = FanSelfTest.run(reader: reader, thermal: thermal)
            FileHandle.standardOutput.write(try FanWire.encode(report))
            FileHandle.standardOutput.write(Data("\n".utf8))
            return 0
        } catch {
            FileHandle.standardError.write(Data("fanhelper self-test: \(error)\n".utf8))
            return 1
        }
    }
}
