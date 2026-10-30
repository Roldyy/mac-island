import CoreAudio
import Foundation

/// The object the IOProc block captures. `current` is only touched on the IO thread.
final class GainProcessor: @unchecked Sendable {
    let cell: GainCell
    private var current: Float
    /// Index of the tap's stream in the input buffer list; nil means "layout unknown": output silence.
    let tapIndex: Int?

    init(cell: GainCell, tapIndex: Int? = 0) {
        self.cell = cell
        self.tapIndex = tapIndex
        self.current = cell.value
    }

    /// Called on the real-time thread.
    func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        let target = cell.value
        GainProcessing.process(input: input, output: output, tapIndex: tapIndex, from: current, to: target)
        current = target
    }
}
