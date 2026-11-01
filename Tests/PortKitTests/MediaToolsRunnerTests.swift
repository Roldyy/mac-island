import Foundation
import Testing
@testable import PortKit

/// Lane W4-D: the supervisor (cancel, timeout, kill after the grace) and the tool table, on a fake clock and a fake
/// process. No program is started.
@Suite struct MediaToolsRunnerTests {
    func supervise(_ handle: FakeProcessHandle, timeout: TimeInterval = 100, grace: TimeInterval = 2,
                   cancelAt: TimeInterval? = nil, clock: FakeClock = FakeClock(),
                   ticks: ((TimeInterval) -> Void)? = nil) -> MediaSuperviseResult {
        let limits = MediaRunLimits(timeout: timeout, graceSeconds: grace, pollInterval: 0.1)
        return MediaProcessSupervisor.supervise(handle, limits: limits,
                                                isCancelled: { cancelAt.map { clock.time >= $0 } ?? false },
                                                clock: clock.clock, onTick: { ticks?($0) })
    }

    @Test func aProgramThatEndsByItselfReturnsItsStatus() {
        let ok = FakeProcessHandle()
        ok.exitsAfter = 3
        var elapsed: [TimeInterval] = []
        let clock = FakeClock()
        #expect(supervise(ok, clock: clock, ticks: { elapsed.append($0) }) == .exited(0))
        #expect(elapsed.count == 3 && elapsed == elapsed.sorted() && elapsed.first == 0, "\(elapsed)")
        #expect(ok.terminateCalls == 0 && ok.killCalls == 0)

        let bad = FakeProcessHandle()
        bad.exitsAfter = 1
        bad.status = 2
        #expect(supervise(bad) == .exited(2))
    }

    @Test func cancelStopsTheProgramWithTerminateAndNeverKillsAWellBehavedOne() {
        let handle = FakeProcessHandle()
        let clock = FakeClock()
        #expect(supervise(handle, cancelAt: 0.35, clock: clock) == .cancelled)
        #expect(handle.terminateCalls == 1 && handle.killCalls == 0)
        #expect(clock.time < 1, "the cancel is seen within a poll or two, not after the timeout")
    }

    @Test func theTimeBudgetStopsTheProgram() {
        let handle = FakeProcessHandle()
        let clock = FakeClock()
        #expect(supervise(handle, timeout: 1.0, clock: clock) == .timedOut)
        #expect(handle.terminateCalls == 1 && handle.killCalls == 0)
        #expect(clock.time >= 1.0 && clock.time < 1.5, "\(clock.time)")
    }

    @Test func aProgramThatIgnoresTerminateIsKilledAfterTheGrace() {
        let handle = FakeProcessHandle()
        handle.ignoresTerminate = true
        let clock = FakeClock()
        #expect(supervise(handle, timeout: 0.5, grace: 2, clock: clock) == .timedOut)
        #expect(handle.terminateCalls == 1 && handle.killCalls == 1)
        #expect(clock.time >= 2.5, "terminate first, kill only once the grace has run out: \(clock.time)")

        let cancelled = FakeProcessHandle()
        cancelled.ignoresTerminate = true
        #expect(supervise(cancelled, cancelAt: 0.2) == .cancelled)
        #expect(cancelled.killCalls == 1)
    }

    @Test func aCancelThatArrivesAsTheProgramEndsStillCountsAsCancelled() {
        let handle = FakeProcessHandle()
        handle.running = false
        let result = MediaProcessSupervisor.supervise(handle, limits: MediaRunLimits(timeout: 10),
                                                      isCancelled: { true }, clock: FakeClock().clock)
        #expect(result == .cancelled, "the output must not be installed after a cancel")
        #expect(handle.terminateCalls == 0)
    }

    @Test func theVideoTimeBudgetIsGenerousButBounded() {
        #expect(MediaToolsRuntime.limits(forVideoSeconds: 0).timeout == 300)
        #expect(MediaToolsRuntime.limits(forVideoSeconds: 60).timeout == 600)
        #expect(MediaToolsRuntime.limits(forVideoSeconds: 1_000_000).timeout == 21_600)
        #expect(MediaToolsRuntime.limits(forVideoSeconds: .nan).timeout == 300)
        #expect(MediaToolsRuntime.limits(forVideoSeconds: -5).timeout == 300)
        #expect(LiveMediaProcessRunner.niceValue == 10, "converters run at a lowered CPU priority")
    }

    // MARK: Tool table

    @Test func everyExternalProgramIsAnAbsoluteSystemPathWithAFrenchReason() {
        #expect(MediaExternalTool.allCases.map(\.path).sorted() == ["/usr/bin/avconvert", "/usr/bin/killall"])
        for tool in MediaExternalTool.allCases {
            #expect(tool.path.hasPrefix("/usr/bin/"))
            #expect(tool.unavailableReason.hasPrefix("Indisponible"))
        }
        #expect(MediaExternalTool.avconvert.unavailableReason.contains("avconvert"))
    }

    @Test func aMissingToolIsReportedAsIndisponibleAndNothingIsLaunched() throws {
        let fileSystem = FakeMediaFileSystem()  // no executable at all
        let runner = LiveMediaProcessRunner(fileSystem: fileSystem, clock: FakeClock().clock)
        let command = try MediaAvconvertCommand.make(source: URL(fileURLWithPath: "/tmp/a.mov"),
                                                     output: URL(fileURLWithPath: "/tmp/stage/Output.mp4"),
                                                     preset: "Preset1280x720", start: 0, duration: 5, multiPass: false)
        var launched = false
        var ticked = false
        let outcome = try runner.run(command, limits: MediaRunLimits(timeout: 5), isCancelled: { false },
                                     launch: { _ in launched = true }, onTick: { _ in ticked = true })
        #expect(outcome == .toolUnavailable(MediaExternalTool.avconvert.unavailableReason))
        #expect(!launched && !ticked)

        #expect(MediaToolAvailability.isAvailable(.avconvert, fileSystem: fileSystem) == false)
        #expect(MediaToolAvailability.unavailableReason(.avconvert, fileSystem: fileSystem)
                == MediaExternalTool.avconvert.unavailableReason)
        fileSystem.executables.insert("/usr/bin/avconvert")
        #expect(MediaToolAvailability.isAvailable(.avconvert, fileSystem: fileSystem))
        #expect(MediaToolAvailability.unavailableReason(.avconvert, fileSystem: fileSystem) == nil)
    }

    @Test func theLogKeepsOnlyTheTailAndNeverGrowsWithoutBound() {
        let log = BoundedLog(limit: 10)
        log.append(Data("0123456789".utf8))
        log.append(Data("abcdef".utf8))
        #expect(log.text == "6789abcdef")
        for _ in 0..<100 { log.append(Data(repeating: 65, count: 1_000)) }
        #expect(log.text.utf8.count == 10)
    }

    @Test func theFailureTextsAreFrenchAndBounded() {
        #expect(MediaToolsText.avconvertFailed("").contains("avconvert n’a donné aucun détail"))
        let long = String(repeating: "x", count: 5_000)
        #expect(MediaToolsText.avconvertFailed(long).count < 400)
        #expect(MediaToolsText.timedOut(minutes: 12).contains("12 min") && MediaToolsText.timedOut(minutes: 12).contains("n’a pas été modifié"))
    }
}
