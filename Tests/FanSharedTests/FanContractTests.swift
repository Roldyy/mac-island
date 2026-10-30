import Foundation
import Security
import Testing
@testable import FanShared

@Suite struct FanContractTests {
    @Test func identifiersAreStable() {
        #expect(FanHelperContract.machServiceName == "be.roldy.macisland.fanhelper")
        #expect(FanHelperContract.teamID == "U3TUL63HHK")
        #expect(FanHelperContract.appIdentifier == "be.roldy.macisland")
        #expect(FanHelperContract.daemonPlistName == "be.roldy.macisland.fanhelper.plist")
        #expect(FanHelperContract.protocolVersion == 1)
        #expect(FanHelperContract.clientRequirement ==
                #"anchor apple generic and certificate leaf[subject.OU] = "U3TUL63HHK" and identifier "be.roldy.macisland""#)
        #expect(FanShared.helperLabel == FanHelperContract.machServiceName)
    }

    @Test func watchdogOutlastsSeveralMissedHeartbeats() {
        #expect(FanHelperContract.watchdogTimeout >= 3 * FanHelperContract.heartbeatInterval)
    }

    /// `setCodeSigningRequirement` throws an Objective-C exception on a malformed string, which
    /// Swift cannot catch: both strings must parse with the Security framework.
    @Test func requirementStringsParse() {
        for text in [FanHelperContract.clientRequirement, FanHelperContract.helperRequirement] {
            var req: SecRequirement?
            #expect(SecRequirementCreateWithString(text as CFString, [], &req) == errSecSuccess)
            #expect(req != nil)
        }
    }

    @Test func xpcInterfaceBuildsWithPlainSecureTypesOnly() {
        let interface = NSXPCInterface(with: FanHelperXPC.self)
        let sel = #selector(FanHelperXPC.perform(command:reply:))
        let argClasses = interface.classes(for: sel, argumentIndex: 0, ofReply: false)
        #expect(argClasses.count == 1)
        #expect(argClasses.contains { ($0 as? AnyClass) == NSData.self })
    }

    @Test func commandsRoundTripThroughTheWireFormat() throws {
        let commands: [FanCommand] = [.setTarget(fan: 1, rpm: 3000.5), .automatic(fan: 0), .allAutomatic]
        for c in commands {
            #expect(try FanWire.decode(FanCommand.self, from: FanWire.encode(c)) == c)
        }
        let state = FanState(protocolVersion: 1, fans: [FanReading(index: 0, actualRPM: 2317, minRPM: 2317,
                                                                    maxRPM: 7826, targetRPM: 2317, mode: .automatic)],
                             maxTemperatureCelsius: 61, manualActive: false)
        #expect(try FanWire.decode(FanState.self, from: FanWire.encode(state)) == state)
    }

    @Test func wireRejectsOversizedAndMalformedPayloads() {
        let big = Data(repeating: 0x20, count: FanHelperContract.maxPayloadBytes + 1)
        #expect(throws: FanWireError.payloadTooLarge) { try FanWire.decode(FanCommand.self, from: big) }
        #expect(throws: (any Error).self) { try FanWire.decode(FanCommand.self, from: Data("{\"nope\":1}".utf8)) }
        #expect(throws: (any Error).self) { try FanWire.decode(FanCommand.self, from: Data("[]".utf8)) }
        // A NaN cannot travel: JSON has no NaN, and the encoder refuses it.
        #expect(throws: (any Error).self) { try FanWire.encode(FanCommand.setTarget(fan: 0, rpm: .nan)) }
    }
}

@Suite struct FanReadServiceTests {
    @Test func readsBothFansFromTheSMC() throws {
        let smc = FakeSMC(actual: 2499.5)
        let fans = try FanReadService.readings(smc)
        #expect(fans.count == 2)
        #expect(fans[1] == FanReading(index: 1, actualRPM: 2499.5, minRPM: 2317, maxRPM: 7826, targetRPM: 2317, mode: .automatic))
    }

    @Test func absurdFanCountIsRefused() {
        let smc = FakeSMC()
        smc.setRaw("FNum", .ui8, [200])
        #expect(throws: (any Error).self) { try FanReadService.readings(smc) }
    }

    @Test func missingKeysGiveNilFieldsNotGuesses() throws {
        let smc = FakeSMC()
        smc.remove("F0Tg")
        smc.remove("F0Md")
        let f = try FanReadService.readings(smc)[0]
        #expect(f.targetRPM == nil)
        #expect(f.mode == .unknown)
    }

    @Test func limitsKeepOnlyFansWithValidMinAndMax() {
        let smc = FakeSMC()
        smc.setFloat("F1Mn", 0)
        let l = FanReadService.limits(smc, policy: FanSafetyPolicy())
        #expect(l[0] == FanLimits(minRPM: 2317, maxRPM: 7826))
        #expect(l[1] == nil)
    }

    @Test func modeValuesMapConservatively() {
        let smc = FakeSMC()
        smc.setRaw("F0Md", .ui8, [1]); #expect(FanReadService.mode(smc, fan: 0) == .manual)
        smc.setRaw("F0Md", .ui8, [0]); #expect(FanReadService.mode(smc, fan: 0) == .automatic)
        smc.setRaw("F0Md", .ui8, [3]); #expect(FanReadService.mode(smc, fan: 0) == .unknown)
    }
}

@Suite struct TemperatureSensorTests {
    @Test func discoveryKeepsOnlyTheConfiguredPrefixes() {
        let names = ["Tp01", "Te05", "TCMz", "TVMR", "TVMr", "Ta00", "F0Ac", "Tg04"].compactMap(SMCKey.init)
        let kept = TemperatureSensors.discover(names, prefixes: TemperatureSensors.defaultPrefixes).map(\.description)
        #expect(kept == ["Tp01", "Te05", "TCMz"])
    }

    @Test func maxIgnoresImplausibleAndMissingReadings() {
        let smc = FakeSMC()
        smc.setFloat("Tp01", 61.5)
        smc.setFloat("Te05", 0)        // unpopulated sensor
        smc.setFloat("TCMz", -4)
        smc.setFloat("Tp02", 72.25)
        let sensors = TemperatureSensors(keys: ["Tp01", "Te05", "TCMz", "Tp02", "Tp99"].compactMap(SMCKey.init))
        #expect(sensors.maxCelsius(smc, plausible: 1...130) == 72.25)
        #expect(TemperatureSensors(keys: []).maxCelsius(smc, plausible: 1...130) == nil)
    }
}
