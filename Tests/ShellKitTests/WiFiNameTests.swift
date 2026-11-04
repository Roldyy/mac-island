import Foundation
import IslandKit
import Testing
@testable import ShellKit

/// A reader driven by hand: no CoreLocation, no CoreWLAN.
@MainActor
private final class FakeSSIDReader: SSIDReading {
    var authorization: LocationAuthorization
    let ssid: String?
    var onAuthorizationChange: (@MainActor () -> Void)?
    private(set) var requests = 0
    /// `readSSID()` is called off the main actor by the chip: its record is lock-protected.
    private final class ReadLog: @unchecked Sendable {
        let lock = NSLock()
        var onMain: [Bool] = []   // Thread.isMainThread of each read
    }
    private nonisolated let record = ReadLog()

    init(_ authorization: LocationAuthorization, ssid: String? = nil) {
        self.authorization = authorization
        self.ssid = ssid
    }

    nonisolated func readSSID() -> String? {
        record.lock.lock(); defer { record.lock.unlock() }
        record.onMain.append(Thread.isMainThread)
        return ssid
    }
    var reads: Int { record.lock.lock(); defer { record.lock.unlock() }; return record.onMain.count }
    var readOnMain: Bool { record.lock.lock(); defer { record.lock.unlock() }; return record.onMain.contains(true) }
    func requestAuthorization() { requests += 1 }
}

@MainActor
@Suite struct WiFiNameTests {
    // MARK: Sanitiser

    @Test func aPlainNameIsKept() {
        #expect(WiFiNameProvider.sanitized("Maison 5G") == "Maison 5G")
        #expect(WiFiNameProvider.sanitized("Café du Port") == "Café du Port")
    }

    @Test func controlsLineBreaksAndBidiOverridesAreDropped() {
        #expect(WiFiNameProvider.sanitized("Bu\u{0000}reau\n\r\t2") == "Bureau2")
        // U+202E (right-to-left override), U+2066 (isolate), U+200B (zero-width space), U+FEFF.
        #expect(WiFiNameProvider.sanitized("\u{202E}moc.evil\u{2066}\u{200B}\u{FEFF}") == "moc.evil")
        #expect(WiFiNameProvider.sanitized("a\u{2028}b\u{2029}c") == "abc")
    }

    @Test func spacesCollapseAndTrim() {
        #expect(WiFiNameProvider.sanitized("  Wi   Fi \u{00A0} Box  ") == "Wi Fi Box")
    }

    @Test func anEmptyNameIsNil() {
        #expect(WiFiNameProvider.sanitized(nil) == nil)
        #expect(WiFiNameProvider.sanitized("") == nil)
        #expect(WiFiNameProvider.sanitized("\u{202E}\u{200B}  \n") == nil)
    }

    @Test func aLongNameIsCutAt24CharactersWithAnEllipsis() throws {
        let exactly = String(repeating: "a", count: 24)
        #expect(WiFiNameProvider.sanitized(exactly) == exactly)
        let long = try #require(WiFiNameProvider.sanitized(String(repeating: "b", count: 60)))
        #expect(long.count == 24 && long.hasSuffix("…"))
        // Counted in characters, not bytes: 30 emoji never split one.
        let emoji = try #require(WiFiNameProvider.sanitized(String(repeating: "📶", count: 30)))
        #expect(emoji.count == 24 && emoji.hasPrefix("📶"))
    }

    // MARK: Provider states

    @Test func authorizedGivesTheSanitisedName() {
        let reader = FakeSSIDReader(.authorized)
        let provider = WiFiNameProvider(reader: reader)
        #expect(provider.name(forWiFi: true, sampled: "\u{202E}Box\n") == "Box")
        #expect(reader.requests == 0)
    }

    @Test func authorizedWithoutANameGivesNil() {
        let provider = WiFiNameProvider(reader: FakeSSIDReader(.authorized, ssid: nil))
        #expect(provider.name(forWiFi: true, sampled: nil) == nil)
    }

    @Test func deniedGivesNilAndNeverAsksNorReads() {
        let reader = FakeSSIDReader(.denied, ssid: "Box")
        let provider = WiFiNameProvider(reader: reader)
        for _ in 0..<5 { #expect(provider.name(forWiFi: true, sampled: "Box") == nil) }
        #expect(reader.requests == 0 && reader.reads == 0)
    }

    @Test func undeterminedAsksOnceOnWiFiAndGivesNil() {
        let reader = FakeSSIDReader(.notDetermined, ssid: "Box")
        let provider = WiFiNameProvider(reader: reader)
        for _ in 0..<5 { #expect(provider.name(forWiFi: true, sampled: nil) == nil) }
        #expect(reader.requests == 1, "one prompt, never two")
        #expect(reader.reads == 0, "the SSID is not read before the permission")
    }

    @Test func offWiFiNeverAsks() {
        let reader = FakeSSIDReader(.notDetermined, ssid: "Box")
        let provider = WiFiNameProvider(reader: reader)
        #expect(provider.name(forWiFi: false, sampled: "Box") == nil)
        #expect(reader.requests == 0)
        // The first time on Wi-Fi is the first request.
        _ = provider.name(forWiFi: true, sampled: nil)
        #expect(reader.requests == 1)
    }

    @Test func theRequestFlagSurvivesAStopAndARestart() {
        let reader = FakeSSIDReader(.notDetermined)
        let provider = WiFiNameProvider(reader: reader)
        provider.begin {}
        _ = provider.name(forWiFi: true, sampled: nil)
        provider.end()
        provider.begin {}
        _ = provider.name(forWiFi: true, sampled: nil)
        #expect(reader.requests == 1)
    }

    @Test func beginAndEndHookTheAuthorizationCallback() {
        let reader = FakeSSIDReader(.notDetermined)
        let provider = WiFiNameProvider(reader: reader)
        provider.begin {}
        #expect(reader.onAuthorizationChange != nil)
        provider.end()
        #expect(reader.onAuthorizationChange == nil)
    }

    // MARK: The chip

    private func snapshot(_ link: NetworkLink, name: String? = nil, ssid: String? = nil) -> NetworkChipSource.Snapshot {
        .init(link: link, vpn: false, down: nil, up: nil, name: name, ssid: ssid)
    }

    @Test func theTitleIsTheNameWhenKnownAndWiFiOtherwise() {
        #expect(NetworkChipSource.reading(snapshot(.wifi, name: "Maison 5G")).primary == "Maison 5G")
        #expect(NetworkChipSource.reading(snapshot(.wifi)).primary == "Wi-Fi")
        // A name never replaces the other titles.
        #expect(NetworkChipSource.reading(snapshot(.wired, name: "Maison")).primary == "Ethernet")
        #expect(NetworkChipSource.reading(snapshot(.offline, name: "Maison")).primary == "Hors ligne")
    }

    @Test func theDebitStaysSecondaryNextToTheName() {
        let reading = NetworkChipSource.reading(.init(link: .wifi, vpn: true, down: 1_200_000, up: 50_000, name: "Box"))
        #expect(reading.primary == "Box")
        #expect(reading.secondary?.hasPrefix("VPN · ↓ ") == true)
    }

    @Test func aRunningChipShowsTheNameOnceAuthorizedAndKeepsWiFiWhenDenied() async throws {
        for (authorization, expected) in [(LocationAuthorization.authorized, "Box"), (.denied, "Wi-Fi"), (.notDetermined, "Wi-Fi")] {
            let reader = FakeSSIDReader(authorization, ssid: "Box")
            let source = NetworkChipSource(sleep: { _ in try await Task.sleep(for: .seconds(3600)) }, watchPath: false,
                                           read: { [] }, nameProvider: WiFiNameProvider(reader: reader))
            // No path monitor in the test: feed the wifi link through the same `apply` the tick uses.
            source.start()
            source.apply(snapshot(.wifi, ssid: "Box"))
            #expect(source.reading?.primary == expected)
            source.stop()
            #expect(source.reading == nil)
        }
    }

    @Test func answeringThePromptRedrawsTheChipWithTheName() async {
        let reader = FakeSSIDReader(.notDetermined, ssid: "Box")
        let source = NetworkChipSource(sleep: { _ in try await Task.sleep(for: .seconds(3600)) }, watchPath: false,
                                       read: { [] }, nameProvider: WiFiNameProvider(reader: reader), initialLink: .wifi)
        source.start()
        for _ in 0..<400 where source.reading == nil { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(source.reading?.primary == "Wi-Fi" && reader.requests == 1)
        var changes = 0
        source.onChange = { changes += 1 }
        reader.authorization = .authorized
        reader.onAuthorizationChange?()
        // The name is read again off the main thread, then the chip redraws.
        for _ in 0..<200 where source.reading?.primary != "Box" { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(source.reading?.primary == "Box" && changes == 1)
        #expect(!reader.readOnMain)
        source.stop()
        #expect(reader.onAuthorizationChange == nil, "stop() unhooks the delegate callback")
    }

    @Test func theNameIsReadInsideTheTickOffTheMainThread() async throws {
        let reader = FakeSSIDReader(.authorized, ssid: "Box")
        let source = NetworkChipSource(sleep: { _ in try await Task.sleep(for: .seconds(3600)) }, watchPath: false,
                                       read: { [] }, nameProvider: WiFiNameProvider(reader: reader), initialLink: .wifi)
        source.start()
        for _ in 0..<400 where source.reading?.primary != "Box" { try await Task.sleep(for: .milliseconds(10)) }
        #expect(source.reading?.primary == "Box")
        #expect(reader.reads >= 1)
        #expect(!reader.readOnMain, "CoreWLAN blocks: the read belongs to the detached tick")
        source.stop()
    }

    @Test func offWiFiTheTickNeverReadsTheName() async throws {
        let reader = FakeSSIDReader(.authorized, ssid: "Box")
        let source = NetworkChipSource(sleep: { _ in try await Task.sleep(for: .seconds(3600)) }, watchPath: false,
                                       read: { [] }, nameProvider: WiFiNameProvider(reader: reader), initialLink: .wired)
        source.start()
        for _ in 0..<400 where source.reading == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(source.reading?.primary == "Ethernet" && reader.reads == 0)
        source.stop()
    }

    @Test func builtinWiresTheLiveProviderUnlessToldOtherwise() {
        let network = StatusChipProviders.builtin(openMonitor: nil, temperature: nil, liveWiFiName: false)
        #expect(network.map(\.kind) == [.network, .load, .disk])
        #expect(StatusChipProviders.builtin(openMonitor: nil, temperature: nil).map(\.kind) == [.network, .load, .disk])
    }
}
