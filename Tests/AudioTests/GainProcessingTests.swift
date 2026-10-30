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
                                           output: outList.unsafeMutablePointer, from: 0.5, to: 0.5)
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
}
