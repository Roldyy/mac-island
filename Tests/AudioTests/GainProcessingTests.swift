import CoreAudio
import Testing
@testable import AudioFeature

@Suite struct GainProcessingTests {
    @Test func constantGainScalesEverySample() {
        let input: [Float] = [1, -1, 0.5, -0.5]
        var output = [Float](repeating: 9, count: 4)
        input.withUnsafeBufferPointer { i in
            output.withUnsafeMutableBufferPointer { o in
                GainProcessing.apply(input: i.baseAddress!, inChannels: 2,
                                     output: o.baseAddress!, outChannels: 2,
                                     frames: 2, from: 0.5, to: 0.5)
            }
        }
        #expect(output == [0.5, -0.5, 0.25, -0.25])
    }

    @Test func rampIsMonotonicAndEndsAtTarget() {
        let frames = 64
        let input = [Float](repeating: 1, count: frames)
        var output = [Float](repeating: 0, count: frames)
        input.withUnsafeBufferPointer { i in
            output.withUnsafeMutableBufferPointer { o in
                GainProcessing.apply(input: i.baseAddress!, inChannels: 1,
                                     output: o.baseAddress!, outChannels: 1,
                                     frames: frames, from: 0, to: 1)
            }
        }
        for k in 1..<frames { #expect(output[k] >= output[k - 1]) }
        #expect(abs(output[frames - 1] - 1) < 1e-6)
        #expect(output[0] < 0.05)
    }

    @Test func extraOutputChannelsAreSilenced() {
        let input: [Float] = [1, 1]
        var output = [Float](repeating: 9, count: 4)
        input.withUnsafeBufferPointer { i in
            output.withUnsafeMutableBufferPointer { o in
                GainProcessing.apply(input: i.baseAddress!, inChannels: 2,
                                     output: o.baseAddress!, outChannels: 4,
                                     frames: 1, from: 1, to: 1)
            }
        }
        #expect(output == [1, 1, 0, 0])
    }

    @Test func extraInputChannelsAreDropped() {
        let input: [Float] = [1, 2, 3]
        var output = [Float](repeating: 9, count: 2)
        input.withUnsafeBufferPointer { i in
            output.withUnsafeMutableBufferPointer { o in
                GainProcessing.apply(input: i.baseAddress!, inChannels: 3,
                                     output: o.baseAddress!, outChannels: 2,
                                     frames: 1, from: 1, to: 1)
            }
        }
        #expect(output == [1, 2])
    }

    @Test func bufferListIsProcessedPairwiseAndSpareOutputsZeroed() {
        let inList = AudioBufferList.allocate(maximumBuffers: 1)
        let outList = AudioBufferList.allocate(maximumBuffers: 2)
        defer { free(inList.unsafeMutablePointer); free(outList.unsafeMutablePointer) }
        var inData: [Float] = [1, 1, 1, 1]
        var out0 = [Float](repeating: 9, count: 4)
        var out1 = [Float](repeating: 9, count: 4)
        inData.withUnsafeMutableBytes { ib in
            out0.withUnsafeMutableBytes { ob0 in
                out1.withUnsafeMutableBytes { ob1 in
                    inList[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 16, mData: ib.baseAddress)
                    outList[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 16, mData: ob0.baseAddress)
                    outList[1] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 16, mData: ob1.baseAddress)
                    GainProcessing.process(input: UnsafePointer(inList.unsafePointer),
                                           output: outList.unsafeMutablePointer, tapIndex: 0, from: 0.5, to: 0.5)
                }
            }
        }
        #expect(out0 == [0.5, 0.5, 0.5, 0.5])
        #expect(out1 == [0, 0, 0, 0])
    }

    @Test func gainCellRoundTrips() {
        let cell = GainCell(initial: 0.25)
        #expect(cell.value == 0.25)
        cell.value = 0.75
        #expect(cell.value == 0.75)
    }

    /// Runs `process` over `inputs` (channels, samples; nil = NULL buffer, a stream switched off) and
    /// `outputBuffers` stereo output buffers of `frames` frames, pre-filled with 9. Returns the outputs.
    private func run(inputs: [(channels: UInt32, samples: [Float]?)], tapIndex: Int?, frames: Int = 2,
                     outputBuffers: Int = 1) -> [[Float]] {
        let inList = AudioBufferList.allocate(maximumBuffers: inputs.count)
        let outList = AudioBufferList.allocate(maximumBuffers: outputBuffers)
        var inPointers: [UnsafeMutablePointer<Float>] = []
        var outPointers: [UnsafeMutablePointer<Float>] = []
        defer {
            inPointers.forEach { $0.deallocate() }
            outPointers.forEach { $0.deallocate() }
            free(inList.unsafeMutablePointer)
            free(outList.unsafeMutablePointer)
        }
        for (k, input) in inputs.enumerated() {
            guard let samples = input.samples else {
                inList[k] = AudioBuffer(mNumberChannels: input.channels, mDataByteSize: 0, mData: nil)
                continue
            }
            let ptr = UnsafeMutablePointer<Float>.allocate(capacity: samples.count)
            ptr.initialize(from: samples, count: samples.count)
            inPointers.append(ptr)
            inList[k] = AudioBuffer(mNumberChannels: input.channels,
                                    mDataByteSize: UInt32(samples.count * 4), mData: ptr)
        }
        for k in 0..<outputBuffers {
            let ptr = UnsafeMutablePointer<Float>.allocate(capacity: frames * 2)
            ptr.initialize(repeating: 9, count: frames * 2)
            outPointers.append(ptr)
            outList[k] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(frames * 8), mData: ptr)
        }
        GainProcessing.process(input: UnsafePointer(inList.unsafePointer), output: outList.unsafeMutablePointer,
                               tapIndex: tapIndex, from: 1, to: 1)
        return outPointers.map { Array(UnsafeBufferPointer(start: $0, count: frames * 2)) }
    }

    @Test func tapIsPlayedNotTheMicWhenTheOutputDeviceAlsoHasInputs() {
        // Aggregate inputs: [device microphone (1 ch), tap (2 ch)].
        let out = run(inputs: [(1, [0.7, 0.7]), (2, [0.1, 0.2, 0.3, 0.4])], tapIndex: 1)
        #expect(out == [[0.1, 0.2, 0.3, 0.4]])
    }

    @Test func disabledMicStreamWithNullBufferNeverReachesTheOutput() {
        let out = run(inputs: [(1, nil), (2, [0.5, 0.5, 0.5, 0.5])], tapIndex: 1)
        #expect(out == [[0.5, 0.5, 0.5, 0.5]])
    }

    @Test func unexpectedLayoutOutputsSilenceNotAWrongStream() {
        let outOfRange = run(inputs: [(1, [0.7, 0.7])], tapIndex: 1)
        #expect(outOfRange == [[0, 0, 0, 0]])
        let unknown = run(inputs: [(2, [0.7, 0.7, 0.7, 0.7])], tapIndex: nil)
        #expect(unknown == [[0, 0, 0, 0]])
        let nullTap = run(inputs: [(2, nil)], tapIndex: 0)
        #expect(nullTap == [[0, 0, 0, 0]])
    }

    @Test func layoutWithoutInputsOnTheOutputDeviceUsesTheOnlyStream() {
        let plan = StreamLayout.plan(aggregateInputChannels: [2], subDeviceInputChannels: [])
        #expect(plan == .init(tapIndex: 0, streamIsOn: [1]))
    }

    @Test func layoutPutsTheTapAfterTheSubDeviceStreamsAndSwitchesThoseOff() {
        let plan = StreamLayout.plan(aggregateInputChannels: [1, 2], subDeviceInputChannels: [1])
        #expect(plan == .init(tapIndex: 1, streamIsOn: [0, 1]))
        let two = StreamLayout.plan(aggregateInputChannels: [1, 1, 2], subDeviceInputChannels: [1, 1])
        #expect(two == .init(tapIndex: 2, streamIsOn: [0, 0, 1]))
    }

    @Test func unrecognisedLayoutHasNoPlan() {
        #expect(StreamLayout.plan(aggregateInputChannels: [], subDeviceInputChannels: []) == nil)
        #expect(StreamLayout.plan(aggregateInputChannels: [2, 1], subDeviceInputChannels: [1]) == nil) // tap not last
        #expect(StreamLayout.plan(aggregateInputChannels: [1, 2, 2], subDeviceInputChannels: [1]) == nil) // extra stream
        #expect(StreamLayout.plan(aggregateInputChannels: [1, 6], subDeviceInputChannels: [1]) == nil) // not stereo
        #expect(StreamLayout.plan(aggregateInputChannels: [2, 2], subDeviceInputChannels: [1]) == nil) // sub streams differ
    }

    @Test func engineWithoutCaptureGrantCreatesNoTap() {
        let gate = CaptureGate()
        let engine = CoreAudioMixerEngine(gate: gate)
        #expect(throws: MixerEngineError.permissionNotGranted) {
            try engine.start(app: "com.example", processes: [1], outputDeviceUID: "none", gain: 0.5)
        }
        #expect(engine.liveApps.isEmpty)
    }
}
