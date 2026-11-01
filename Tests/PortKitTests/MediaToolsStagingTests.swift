import AVFoundation
import Foundation
import IslandTestSupport
import Testing
@testable import PortKit

/// Lane W4-D: the private staging folders, the lifecycle (start, stop, quit, kill switch) and the media service end to
/// end with a FAKE converter. One serialized main-actor suite: `MediaStaging` and `MediaToolsRuntime.runner` are
/// process-wide, and these tests are the only ones that touch them.
///
/// Waits tolerate a full-run main-actor backlog: the deadlines are 120 s, with no millisecond budget.
@MainActor
@Suite(.serialized) struct MediaToolsStagingTests {
    final class Bench {
        let defaults: UserDefaults
        let cleanup: () -> Void
        let fileSystem = FakeMediaFileSystem()

        init() {
            let bench = TestDefaults.make()
            defaults = bench.defaults
            cleanup = bench.cleanup
            MediaStaging.journalDefaults = bench.defaults
            MediaStaging.cleanupAll(defaults: bench.defaults, fileSystem: fileSystem)
        }

        func finish() {
            MediaStaging.journalDefaults = nil
            cleanup()
        }

        func folder(_ name: String, files: [String] = ["Output.mp4"]) -> URL {
            let path = "/stage/\(UUID().uuidString)-\(name)"
            fileSystem.directories.insert(path)
            for file in files { fileSystem.files["\(path)/\(file)"] = Data("x".utf8) }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    // MARK: Registry

    @Test func aRegisteredFolderIsOwnerOnlyTrackedAndJournaled() {
        let bench = Bench()
        defer { bench.finish() }
        let dir = bench.folder("a")
        bench.fileSystem.modes[dir.path] = 0o755
        MediaStaging.register(dir, defaults: bench.defaults, fileSystem: bench.fileSystem)
        #expect(bench.fileSystem.permissions(atPath: dir.path) == 0o700, "0700, whatever the system created")
        #expect(MediaStaging.owns(dir) && MediaStaging.liveDirectories.contains(dir.path))
        #expect(MediaStaging.journal(bench.defaults) == [dir.path])
    }

    @Test func discardRemovesTheWholeFolderThisProcessMadeAndForgetsIt() {
        let bench = Bench()
        defer { bench.finish() }
        let dir = bench.folder("b", files: ["Output.mp4", "sidecar.tmp"])
        MediaStaging.register(dir, defaults: bench.defaults, fileSystem: bench.fileSystem)
        MediaStaging.discard(dir.appendingPathComponent("Output.mp4"), defaults: bench.defaults, fileSystem: bench.fileSystem)
        #expect(!bench.fileSystem.fileExists(atPath: dir.path), "folder and sidecars are gone")
        #expect(!MediaStaging.owns(dir) && MediaStaging.journal(bench.defaults).isEmpty)
        MediaStaging.discard(dir.appendingPathComponent("Output.mp4"), defaults: bench.defaults, fileSystem: bench.fileSystem)
        #expect(bench.fileSystem.removed == [dir.path], "a second discard removes nothing more")
    }

    @Test func discardNeverRemovesTheUsersSourceOrAFolderItDidNotMake() {
        let bench = Bench()
        defer { bench.finish() }
        let userDir = bench.folder("movies", files: ["clip.mov", "Output.mp4", "Notes.txt"])
        // A staged file that lives in the user's folder (a regression would put it there): only it goes.
        MediaStaging.discard(userDir.appendingPathComponent("Output.mp4"), defaults: bench.defaults, fileSystem: bench.fileSystem)
        #expect(bench.fileSystem.fileExists(atPath: userDir.path))
        #expect(bench.fileSystem.files["\(userDir.path)/clip.mov"] != nil && bench.fileSystem.files["\(userDir.path)/Notes.txt"] != nil)
        #expect(bench.fileSystem.files["\(userDir.path)/Output.mp4"] == nil)
        // Asked to discard the source itself: nothing is removed, because its name is not a staged name.
        MediaStaging.discard(userDir.appendingPathComponent("clip.mov"), defaults: bench.defaults, fileSystem: bench.fileSystem)
        #expect(bench.fileSystem.files["\(userDir.path)/clip.mov"] != nil)
        MediaStaging.discard(userDir.appendingPathComponent("Notes.txt"), defaults: bench.defaults, fileSystem: bench.fileSystem)
        #expect(bench.fileSystem.files["\(userDir.path)/Notes.txt"] != nil)
        #expect(bench.fileSystem.removed == ["\(userDir.path)/Output.mp4"])
    }

    @Test func cleanupAllRemovesEveryLiveFolderAndEmptiesTheJournal() {
        let bench = Bench()
        defer { bench.finish() }
        let first = bench.folder("c1")
        let second = bench.folder("c2")
        let bystander = bench.folder("other")
        MediaStaging.register(first, defaults: bench.defaults, fileSystem: bench.fileSystem)
        MediaStaging.register(second, defaults: bench.defaults, fileSystem: bench.fileSystem)
        MediaStaging.cleanupAll(defaults: bench.defaults, fileSystem: bench.fileSystem)
        #expect(!bench.fileSystem.fileExists(atPath: first.path) && !bench.fileSystem.fileExists(atPath: second.path))
        #expect(bench.fileSystem.fileExists(atPath: bystander.path), "only what was registered")
        #expect(MediaStaging.liveDirectories.isEmpty && MediaStaging.journal(bench.defaults).isEmpty)
        MediaStaging.cleanupAll(defaults: bench.defaults, fileSystem: bench.fileSystem)  // idempotent
    }

    @Test func theSweepRemovesOnlyWhatADeadRunLeftAndOnlyIfItHoldsNothingElse() {
        let bench = Bench()
        defer { bench.finish() }
        let leftover = bench.folder("leftover")
        let mixed = bench.folder("mixed", files: ["Output.mp4", "precious.txt"])
        let gone = URL(fileURLWithPath: "/stage/\(UUID().uuidString)-gone")
        let linked = URL(fileURLWithPath: "/stage/\(UUID().uuidString)-link")
        bench.fileSystem.directories.insert(linked.path)
        bench.fileSystem.links.insert(linked.path)
        bench.fileSystem.files["\(linked.path)/Output.mp4"] = Data("x".utf8)
        let live = bench.folder("live")
        MediaStaging.register(live, defaults: bench.defaults, fileSystem: bench.fileSystem)
        bench.defaults.set([leftover.path, mixed.path, gone.path, linked.path, live.path], forKey: MediaStaging.journalKey)

        let removed = MediaStaging.sweepLeftovers(defaults: bench.defaults, fileSystem: bench.fileSystem)
        #expect(removed == [leftover.path])
        #expect(!bench.fileSystem.fileExists(atPath: leftover.path))
        #expect(bench.fileSystem.files["\(mixed.path)/precious.txt"] != nil, "a folder with anything else stays")
        #expect(bench.fileSystem.files["\(linked.path)/Output.mp4"] != nil, "a link is never followed")
        #expect(bench.fileSystem.fileExists(atPath: live.path), "this process's own folder is not a leftover")
        let kept = Set(MediaStaging.journal(bench.defaults))
        #expect(kept == [mixed.path, linked.path, live.path], "the missing one is dropped, the refused ones stay listed")
    }

    // MARK: Lifecycle

    @Test func stopBeforeAnyStartCancelsNothing() {
        let bench = Bench()
        defer { bench.finish() }
        let saved = MediaToolsLifecycle.cancelJobs
        defer { MediaToolsLifecycle.cancelJobs = saved; MediaToolsLifecycle.started = false }
        var cancels = 0
        MediaToolsLifecycle.cancelJobs = { cancels += 1 }
        MediaToolsLifecycle.started = false
        MediaToolsLifecycle.stop(defaults: bench.defaults, fileSystem: bench.fileSystem)
        #expect(cancels == 0, "a Mac where the feature stayed off builds and cancels nothing")
    }

    @Test func startSweepsLeftoversAndStopOrQuitCancelsTheJobAndRemovesTheFolders() {
        let bench = Bench()
        defer { bench.finish() }
        let saved = MediaToolsLifecycle.cancelJobs
        defer {
            MediaToolsLifecycle.cancelJobs = saved
            MediaToolsLifecycle.stop(defaults: bench.defaults, fileSystem: bench.fileSystem)
            MediaToolsLifecycle.started = false
        }
        var cancels = 0
        MediaToolsLifecycle.cancelJobs = { cancels += 1 }
        let leftover = bench.folder("dead")
        bench.defaults.set([leftover.path], forKey: MediaStaging.journalKey)

        MediaToolsLifecycle.start(defaults: bench.defaults, fileSystem: bench.fileSystem)
        MediaToolsLifecycle.start(defaults: bench.defaults, fileSystem: bench.fileSystem)  // idempotent
        #expect(cancels == 0, "starting never cancels")
        #expect(!bench.fileSystem.fileExists(atPath: leftover.path), "the dead run's folder is removed at the start")

        let live = bench.folder("running")
        MediaStaging.register(live, defaults: bench.defaults, fileSystem: bench.fileSystem)
        MediaToolsLifecycle.stop(defaults: bench.defaults, fileSystem: bench.fileSystem)
        #expect(cancels == 1, "the kill switch, safe mode, a switch-off all stop the running job")
        #expect(!bench.fileSystem.fileExists(atPath: live.path) && MediaStaging.liveDirectories.isEmpty)

        let again = bench.folder("running2")
        MediaStaging.register(again, defaults: bench.defaults, fileSystem: bench.fileSystem)
        MediaToolsLifecycle.quit(defaults: bench.defaults, fileSystem: bench.fileSystem)
        #expect(cancels == 2 && !bench.fileSystem.fileExists(atPath: again.path), "and so does the quit")
    }

    // MARK: The media service with a fake converter

    /// A one-second 64x64 H.264 movie, written by AVFoundation. The converter itself is NEVER started: the fake runner
    /// answers in its place.
    static func makeMovie(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64,
        ])
        writer.add(input)
        try #require(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<30 {
            let deadline = Date().addingTimeInterval(120)
            while !input.isReadyForMoreMediaData, Date() < deadline { try await Task.sleep(nanoseconds: 5_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            if let base = CVPixelBufferGetBaseAddress(pixels) {
                memset(base, Int32(frame * 8), CVPixelBufferGetDataSize(pixels))
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        try #require(writer.status == .completed, "\(String(describing: writer.error))")
    }

    struct Scene {
        let directory: URL
        let source: URL
        let output: URL
    }

    /// A temp folder with a movie whose NAME is hostile (spaces, quote, leading dash) and a taken output name.
    func makeScene() async throws -> Scene {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mis-media-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("-my clip \"v1\".mp4")
        try await Self.makeMovie(at: source)
        let output = directory.appendingPathComponent("-my clip \"v1\"-compressed.mp4")
        try Data("precious".utf8).write(to: output)
        return Scene(directory: directory, source: source, output: output)
    }

    func options() -> MediaVideoOptions {
        MediaVideoOptions(start: 0, end: 0, quality: 0.68, maxDimension: 1280, fps: 30, keepAudio: true, codec: .h264)
    }

    func wait(for service: MediaService, until done: (MediaServiceState) -> Bool) async throws -> MediaServiceState {
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if done(service.state) { return service.state }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return service.state
    }

    func isTerminal(_ state: MediaServiceState) -> Bool {
        switch state {
        case .completed, .failed, .cancelled: true
        default: false
        }
    }

    @Test func aVideoRunPassesOneFixedArrayWritesNextToTheSourceAndNeverOverwrites() async throws {
        let bench = Bench()
        defer { bench.finish() }
        let scene = try await makeScene()
        defer { try? FileManager.default.removeItem(at: scene.directory) }
        let runner = FakeMediaProcessRunner()
        let savedRunner = MediaToolsRuntime.runner
        MediaToolsRuntime.runner = runner
        defer { MediaToolsRuntime.runner = savedRunner }
        let sourceBefore = try Data(contentsOf: scene.source)

        let service = MediaService(replacesExistingOutputs: false)
        service.compressVideo(inputURL: scene.source, outputURL: scene.output, options: options())
        let state = try await wait(for: service, until: isTerminal)

        guard case let .completed(result) = state else {
            Issue.record("expected a completed run, got \(state)")
            return
        }
        // One call, one fixed array, the user's odd file name as a single element.
        let command = try #require(runner.commands.first)
        #expect(runner.commands.count == 1 && command.executablePath == "/usr/bin/avconvert")
        let args = command.arguments
        #expect(args.first == "--source" && args[1] == scene.source.path)
        #expect(MediaAvconvertCommand.allowedPresets.contains(args[3]))
        let outputIndex = try #require(args.firstIndex(of: "--output"))
        let staged = URL(fileURLWithPath: args[outputIndex + 1])
        #expect(staged.deletingLastPathComponent() != scene.directory, "the converter writes into a staging folder, not beside the source")
        #expect(staged.lastPathComponent.hasPrefix("Output"))
        #expect(runner.outputFolderModes == [0o700], "the staging folder is owner-only: \(runner.outputFolderModes)")
        // The taken name was kept, the result went to the next free one.
        #expect(try Data(contentsOf: scene.output) == Data("precious".utf8), "never overwritten")
        let written = try #require(result.outputURL)
        #expect(written.deletingLastPathComponent() == scene.directory)
        // (the ported name sanitiser drops a leading dash or dot, as it does for every default name)
        #expect(written.lastPathComponent == "my clip \"v1\"-compressed 2.mp4", "\(written.lastPathComponent)")
        #expect(try Data(contentsOf: written) == Data("fake-encoded".utf8))
        #expect(try Data(contentsOf: scene.source) == sourceBefore, "the source is untouched")
        // The time budget scales with the clip, and the staging folder is gone.
        #expect((runner.limits.first?.timeout ?? 0) >= 300, "a time budget was passed")
        #expect(MediaStaging.liveDirectories.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: staged.deletingLastPathComponent().path))
    }

    @Test func aMissingConverterIsReportedAsIndisponibleAndLeavesNoFile() async throws {
        let bench = Bench()
        defer { bench.finish() }
        let scene = try await makeScene()
        defer { try? FileManager.default.removeItem(at: scene.directory) }
        let runner = FakeMediaProcessRunner()
        runner.outcome = .toolUnavailable(MediaExternalTool.avconvert.unavailableReason)
        let savedRunner = MediaToolsRuntime.runner
        MediaToolsRuntime.runner = runner
        defer { MediaToolsRuntime.runner = savedRunner }

        let service = MediaService(replacesExistingOutputs: false)
        service.compressVideo(inputURL: scene.source, outputURL: scene.output, options: options())
        let state = try await wait(for: service, until: isTerminal)
        #expect(state == .failed(.failed(MediaExternalTool.avconvert.unavailableReason)))
        let names = try FileManager.default.contentsOfDirectory(atPath: scene.directory.path).sorted()
        #expect(names.count == 2, "only the source and the pre-existing output: \(names)")
        #expect(MediaStaging.liveDirectories.isEmpty)
    }

    @Test func aTimedOutConverterFailsInFrenchAndLeavesNoFile() async throws {
        let bench = Bench()
        defer { bench.finish() }
        let scene = try await makeScene()
        defer { try? FileManager.default.removeItem(at: scene.directory) }
        let runner = FakeMediaProcessRunner()
        runner.outcome = .timedOut
        let savedRunner = MediaToolsRuntime.runner
        MediaToolsRuntime.runner = runner
        defer { MediaToolsRuntime.runner = savedRunner }

        let service = MediaService(replacesExistingOutputs: false)
        service.compressVideo(inputURL: scene.source, outputURL: scene.output, options: options())
        let state = try await wait(for: service, until: isTerminal)
        guard case let .failed(.failed(message)) = state else {
            Issue.record("expected a failure, got \(state)")
            return
        }
        #expect(message.contains("durée maximale") && message.contains("n’a pas été modifié"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: scene.directory.path).count == 2)
    }

    @Test func aFailingConverterReportsItsLogAndAnExitCodeNeverInstallsAnOutput() async throws {
        let bench = Bench()
        defer { bench.finish() }
        let scene = try await makeScene()
        defer { try? FileManager.default.removeItem(at: scene.directory) }
        let runner = FakeMediaProcessRunner()
        runner.outcome = .finished(status: 1, log: "Error: unsupported codec")
        let savedRunner = MediaToolsRuntime.runner
        MediaToolsRuntime.runner = runner
        defer { MediaToolsRuntime.runner = savedRunner }

        let service = MediaService(replacesExistingOutputs: false)
        service.compressVideo(inputURL: scene.source, outputURL: scene.output, options: options())
        let state = try await wait(for: service, until: isTerminal)
        #expect(state == .failed(.failed("La conversion vidéo a échoué : Error: unsupported codec")))
        #expect(try FileManager.default.contentsOfDirectory(atPath: scene.directory.path).count == 2)
    }

    @Test func cancelStopsTheRunAndNothingIsInstalled() async throws {
        let bench = Bench()
        defer { bench.finish() }
        let scene = try await makeScene()
        defer { try? FileManager.default.removeItem(at: scene.directory) }
        let runner = FakeMediaProcessRunner()
        runner.blocksUntilCancelled = true
        let savedRunner = MediaToolsRuntime.runner
        MediaToolsRuntime.runner = runner
        defer { MediaToolsRuntime.runner = savedRunner }

        let service = MediaService(replacesExistingOutputs: false)
        service.compressVideo(inputURL: scene.source, outputURL: scene.output, options: options())
        let deadline = Date().addingTimeInterval(120)
        while !runner.entered, Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(runner.entered, "the run reached the converter")
        // What the kill switch does through `MediaToolsLifecycle.cancelJobs` (live: `MediaService.shared.cancel`).
        service.cancel(immediately: true)
        let state = try await wait(for: service, until: isTerminal)
        #expect(state == .cancelled)
        let deadlineFolders = Date().addingTimeInterval(120)
        while !MediaStaging.liveDirectories.isEmpty, Date() < deadlineFolders { try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(MediaStaging.liveDirectories.isEmpty, "the staging folder is removed after a cancel")
        #expect(try FileManager.default.contentsOfDirectory(atPath: scene.directory.path).count == 2)
        #expect(try Data(contentsOf: scene.output) == Data("precious".utf8))
    }
}
