import Foundation

/// One float shared between the main thread (writer) and the IOProc (reader).
///
/// Real-time rule: the IOProc takes no lock. A naturally aligned 32-bit load or store is a single
/// instruction on arm64 and x86_64, so a reader sees the old or the new value, never a torn one.
/// Swift has no atomics below macOS 15 (`Synchronization`), so this is a relaxed plain access: formally a
/// data race in the Swift memory model, benign for one writer and one reader of one float, and no
/// ordering with other data is relied on. The memory is a manual allocation so it never moves.
final class GainCell: @unchecked Sendable {
    private let pointer: UnsafeMutablePointer<Float>

    init(initial: Float) {
        pointer = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        pointer.initialize(to: initial)
    }

    deinit { pointer.deallocate() }

    var value: Float {
        get { pointer.pointee }
        set { pointer.pointee = newValue }
    }
}
