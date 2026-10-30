import Foundation

/// Slider position (what `appVolumes` stores when `appVolumesArePositions` is true) <-> linear gain.
///
/// Interpretation chosen: positions. The migrated flag says so, and the only data on this machine
/// (two apps at 0.0) cannot contradict it. The old app's exact taper is UNKNOWN, so this is a
/// square law: pure, monotonic, 0 -> 0 and 1 -> 1 (never a boost), roughly -12 dB at mid travel,
/// which feels even on a slider where a linear gain crowds all the change near the top.
enum VolumeCurve {
    static func gain(forPosition position: Double) -> Float {
        guard position.isFinite else { return 0 }
        let p = min(max(position, 0), 1)
        return Float(p * p)
    }

    static func position(forGain gain: Float) -> Double {
        guard gain.isFinite else { return 0 }
        return Double(min(max(gain, 0), 1)).squareRoot()
    }
}
