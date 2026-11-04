import Foundation
import IslandKit
import ShellKit
import Testing
@testable import IPScannerFeature

/// What the copy action wrote and what the opener did.
private final class Recorder: @unchecked Sendable {
    var copied: [String] = []
    var opened = 0
}

@MainActor
@Suite struct IPChipSourceTests {
    private let lan = [Fixtures.interface("192.168.1.20")]

    private func source(interfaces: [LocalInterface]? = nil, vpn: Bool = false, fetcher: FakeFetcher = FakeFetcher(),
                        recorder: Recorder = Recorder(), openScanner: Bool = true,
                        sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in try await Task.sleep(for: .seconds(3600)) })
        -> IPChipSource {
        var opener: (@MainActor () -> Void)?
        if openScanner { opener = { recorder.opened += 1 } }
        return IPChipSource(
            interfaces: FakeInterfaces(list: interfaces ?? lan),
            tunnelReadings: { () -> [InterfaceReading] in
                vpn ? [InterfaceReading(name: "utun4", isUp: true, hasIPv4: true, counters: nil)] : []
            },
            fetcher: fetcher, copy: { recorder.copied.append($0) },
            openScanner: opener,
            sleep: sleep, watchPath: false)
    }

    private func action(_ id: String, in source: IPChipSource) throws -> StatusChipAction {
        try #require(source.reading?.actions.first { $0.id == id })
    }

    // MARK: Formatting

    @Test func theLocalAddressIsThePrimaryTextAndNothingElse() {
        let chip = source()
        chip.start()
        #expect(chip.kind == .ip)
        #expect(chip.reading?.primary == "192.168.1.20")
        #expect(chip.reading?.secondary == nil)
        #expect(chip.reading?.level == .normal)
        chip.stop()
    }

    @Test func thePrimaryInterfaceComesFirst() {
        let chip = source(interfaces: [Fixtures.interface("10.0.0.5", cidr: "10.0.0.0/24", gateway: nil),
                                       Fixtures.interface("192.168.1.20")])
        chip.start()
        #expect(chip.reading?.primary == "10.0.0.5", "the provider already sorts the primary first")
        chip.stop()
    }

    @Test func aVPNShowsTheCapsuleInSecondary() {
        let chip = source(vpn: true)
        chip.start()
        #expect(chip.reading?.secondary == "VPN actif")
        chip.stop()
    }

    @Test func noInterfaceMeansNoChip() {
        let chip = source(interfaces: [])
        chip.start()
        #expect(chip.reading == nil)
        chip.stop()
    }

    @Test func pureFormattingJoinsPublicAndVPN() {
        let both = IPChipSource.reading(local: "192.168.1.20", vpn: true, publicIP: "203.0.113.9")
        #expect(both.secondary == "Publique 203.0.113.9 · VPN actif")
        #expect(IPChipSource.reading(local: "a", vpn: false, publicIP: nil, failed: true).secondary == "IP publique indisponible")
        #expect(IPChipSource.reading(local: "a", vpn: false, publicIP: nil, fetching: true).secondary == "Recherche…")
    }

    // MARK: Actions

    @Test func theActionsAreTheThreeTitlesInOrder() {
        let chip = source()
        chip.start()
        #expect(chip.reading?.actions.map(\.title) == ["Copier l’adresse locale", "Afficher l’IP publique", "Ouvrir le scanner IP"])
        chip.stop()
    }

    @Test func withoutAnOpenerOrAnAvailableTabThereIsNoScannerAction() {
        let chip = source(openScanner: false)
        chip.start()
        #expect(chip.reading?.actions.map(\.id) == ["copy-local", "public-ip"])
        chip.stop()
        let off = IPChipSource(interfaces: FakeInterfaces(list: lan), tunnelReadings: { [] }, fetcher: FakeFetcher(), copy: { _ in },
                               openScanner: {}, scannerAvailable: { false }, watchPath: false)
        off.start()
        #expect(off.reading?.actions.map(\.id) == ["copy-local", "public-ip"])
        off.stop()
    }

    @Test func copyPutsTheLocalAddressOnThePasteboardHook() throws {
        let recorder = Recorder()
        let chip = source(recorder: recorder)
        chip.start()
        try action("copy-local", in: chip).handler()
        #expect(recorder.copied == ["192.168.1.20"])
        try action("scanner", in: chip).handler()
        #expect(recorder.opened == 1)
        chip.stop()
    }

    // MARK: Public IP: only on the click

    @Test func nothingIsFetchedByStartOrByARefresh() {
        let fetcher = FakeFetcher()
        let chip = source(fetcher: fetcher)
        chip.start()
        chip.refresh()
        chip.refresh()
        #expect(fetcher.urls.isEmpty)
        chip.stop()
        #expect(fetcher.urls.isEmpty)
    }

    @Test func theClickFetchesOnceAndShowsTheAnswer() async throws {
        let fetcher = FakeFetcher(answer: "203.0.113.9\n")
        let chip = source(vpn: true, fetcher: fetcher)
        chip.start()
        try action("public-ip", in: chip).handler()
        #expect(chip.reading?.secondary == "Recherche… · VPN actif")
        await chip.pendingFetch?.value
        #expect(fetcher.urls == [PublicIPLookup.url])
        #expect(chip.reading?.secondary == "Publique 203.0.113.9 · VPN actif")
        chip.stop()
    }

    @Test func aSecondClickWhileFetchingDoesNotSendASecondRequest() throws {
        let fetcher = FakeFetcher()
        let chip = source(fetcher: fetcher)
        chip.start()
        let handler = try action("public-ip", in: chip).handler
        handler()
        handler()
        // Only one task was created for two clicks, and it has not run yet.
        #expect(fetcher.urls.isEmpty)
        chip.stop()
    }

    @Test func anInvalidAnswerShowsUnavailable() async throws {
        let chip = source(fetcher: FakeFetcher(answer: "<html>nope</html>"))
        chip.start()
        try action("public-ip", in: chip).handler()
        await chip.pendingFetch?.value
        #expect(chip.reading?.secondary == "IP publique indisponible")
        chip.stop()
    }

    @Test func thePublicIPIsForgottenAfterSixtySeconds() async throws {
        let waited = WaitedDurations()
        let chip = source(sleep: { duration in waited.add(duration) })
        chip.start()
        try action("public-ip", in: chip).handler()
        await chip.pendingFetch?.value
        await chip.waitForForgetting()
        #expect(waited.values == [.seconds(60)])
        #expect(IPChipSource.publicIPDuration == .seconds(60))
        #expect(chip.reading?.secondary == nil, "forgotten: back to the local address alone")
        chip.stop()
    }

    @Test func stopClearsAShownPublicIPAndEverythingElse() async throws {
        let chip = source(fetcher: FakeFetcher(answer: "203.0.113.9"))
        chip.start()
        try action("public-ip", in: chip).handler()
        await chip.pendingFetch?.value
        #expect(chip.reading?.secondary == "Publique 203.0.113.9")
        chip.stop()
        #expect(chip.reading == nil)
        // A restart shows the local address only: the public one was not kept.
        chip.start()
        #expect(chip.reading?.secondary == nil)
        chip.stop()
    }

    @Test func aLateAnswerAfterStopIsDropped() async throws {
        let chip = source(fetcher: FakeFetcher(answer: "203.0.113.9"))
        chip.start()
        try action("public-ip", in: chip).handler()
        let pending = chip.pendingFetch
        chip.stop()
        await pending?.value
        #expect(chip.reading == nil)
    }

    @Test func startAndStopAreIdempotentAndOnChangeFiresOnlyOnChange() {
        let chip = source()
        var changes = 0
        chip.onChange = { changes += 1 }
        chip.start()
        chip.start()
        chip.refresh()
        #expect(changes == 1)
        chip.stop()
        chip.stop()
        #expect(chip.reading == nil)
    }
}

/// The durations a fake sleeper was asked for.
final class WaitedDurations: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [Duration] = []
    func add(_ duration: Duration) { lock.withLock { list.append(duration) } }
    var values: [Duration] { lock.withLock { list } }
}
