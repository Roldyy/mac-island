import CoreGraphics
import Foundation

enum ThumbnailLimits {
    static let maxWindows = 6
    static let maxSize = CGSize(width: 200, height: 130)

    static func cap<T>(_ items: [T]) -> [T] { Array(items.prefix(maxWindows)) }

    /// Aspect fit, never upscaled, whole points.
    static func fit(_ size: CGSize, into max: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, max.width > 0, max.height > 0 else { return .zero }
        let scale = min(1, max.width / size.width, max.height / size.height)
        return CGSize(width: (size.width * scale).rounded(.down), height: (size.height * scale).rounded(.down))
    }
}

/// At most one capture per key per interval.
struct CaptureThrottle {
    let minInterval: TimeInterval
    private var last: [Int32: TimeInterval] = [:]

    init(minInterval: TimeInterval) { self.minInterval = minInterval }

    mutating func shouldCapture(key: Int32, now: TimeInterval) -> Bool {
        if let t = last[key], now - t < minInterval { return false }
        last[key] = now
        return true
    }
    mutating func reset() { last.removeAll() }
}
