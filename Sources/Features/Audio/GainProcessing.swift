import CoreAudio
import Foundation

/// The sample loop of the IOProc. No allocation, no lock, no logging, no Objective-C.
/// Assumes Float32 linear PCM (what aggregate devices expose), interleaved per buffer.
enum GainProcessing {
    /// Copy `frames` frames from `input` to `output`, scaled by a gain that ramps linearly from
    /// `from` (exclusive) to `to` (reached on the last frame) so a slider move never clicks.
    /// Channels beyond the common count are dropped (input) or silenced (output).
    static func apply(input: UnsafePointer<Float>, inChannels: Int,
                      output: UnsafeMutablePointer<Float>, outChannels: Int,
                      frames: Int, from: Float, to: Float) {
        guard frames > 0, inChannels > 0, outChannels > 0 else { return }
        let common = min(inChannels, outChannels)
        let step = (to - from) / Float(frames)
        for f in 0..<frames {
            let g = from + step * Float(f + 1)
            let i = f * inChannels
            let o = f * outChannels
            var c = 0
            while c < common {
                output[o + c] = input[i + c] * g
                c += 1
            }
            while c < outChannels {
                output[o + c] = 0
                c += 1
            }
        }
    }

    /// The tap's stream (`tapIndex` in the input buffer list, found by `StreamLayout`, never assumed to be
    /// buffer 0: a device with a microphone puts its input streams in the same list) feeds the first output
    /// buffer; any other output buffer is silenced. A nil index, an index outside the list or a NULL tap
    /// buffer (a stream switched off) outputs silence rather than some other stream.
    static func process(input: UnsafePointer<AudioBufferList>,
                        output: UnsafeMutablePointer<AudioBufferList>,
                        tapIndex: Int?, from: Float, to: Float) {
        let inBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outBuffers = UnsafeMutableAudioBufferListPointer(output)
        let floatSize = MemoryLayout<Float>.size
        for index in 0..<outBuffers.count {
            let out = outBuffers[index]
            guard let outData = out.mData else { continue }
            let outChannels = Int(out.mNumberChannels)
            let outBytes = Int(out.mDataByteSize)
            guard outChannels > 0 else { continue }
            let outFrames = outBytes / (floatSize * outChannels)
            var done = 0
            if index == 0, let tapIndex, tapIndex >= 0, tapIndex < inBuffers.count {
                let inp = inBuffers[tapIndex]
                let inChannels = Int(inp.mNumberChannels)
                if let inData = inp.mData, inChannels > 0 {
                    let frames = min(outFrames, Int(inp.mDataByteSize) / (floatSize * inChannels))
                    apply(input: inData.assumingMemoryBound(to: Float.self), inChannels: inChannels,
                          output: outData.assumingMemoryBound(to: Float.self), outChannels: outChannels,
                          frames: frames, from: from, to: to)
                    done = frames * outChannels * floatSize
                }
            }
            if done < outBytes {
                memset(outData + done, 0, outBytes - done)
            }
        }
    }
}

/// Which input stream of the aggregate is the tap, as a pure decision over channel counts.
enum StreamLayout {
    struct Plan: Equatable {
        var tapIndex: Int
        /// One flag per aggregate input stream for `kAudioDevicePropertyIOProcStreamUsage`.
        var streamIsOn: [UInt32]
    }

    /// Expected layout: the output device's own input streams first (same channel counts as the device
    /// reports), then exactly one stream, the stereo tap, last. Anything else has no plan: the caller
    /// must not run the IOProc on a layout it cannot name. The order is UNKNOWN from the headers; the
    /// checks above make a wrong guess fail closed in the usual cases, and it needs a real
    /// headset to be proven.
    static func plan(aggregateInputChannels: [Int], subDeviceInputChannels: [Int], tapChannels: Int = 2) -> Plan? {
        let n = subDeviceInputChannels.count
        guard aggregateInputChannels.count == n + 1,
              Array(aggregateInputChannels.prefix(n)) == subDeviceInputChannels,
              aggregateInputChannels[n] == tapChannels else { return nil }
        return Plan(tapIndex: n, streamIsOn: [UInt32](repeating: 0, count: n) + [1])
    }
}
