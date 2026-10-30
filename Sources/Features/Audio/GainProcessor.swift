import CoreAudio
import Foundation

/// The object the IOProc block captures. `current` is only touched on the IO thread.
final class GainProcessor: @unchecked Sendable {
    let cell: GainCell
    private var current: Float

    init(cell: GainCell) {
        self.cell = cell
        self.current = cell.value
    }

    /// Called on the real-time thread.
    func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        let target = cell.value
        GainProcessing.process(input: input, output: output, from: current, to: target)
        current = target
    }
}
