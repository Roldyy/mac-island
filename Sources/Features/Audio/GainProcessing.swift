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

    /// Buffers are paired by index (covers one interleaved buffer and one-buffer-per-channel alike).
    /// An output buffer with no input partner is silenced.
    static func process(input: UnsafePointer<AudioBufferList>,
                        output: UnsafeMutablePointer<AudioBufferList>,
                        from: Float, to: Float) {
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
            if index < inBuffers.count {
                let inp = inBuffers[index]
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
