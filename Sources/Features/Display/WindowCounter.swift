import CoreGraphics
import Foundation

/// Counts visible windows per owner pid. Layer 0 on-screen windows only, which needs no
/// Screen Recording permission (window titles are never read).
enum WindowCounter {
    static let minimumSide: Double = 8

    static func currentCounts() -> [Int32: Int] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        return counts(from: (info as? [[String: Any]]) ?? [])
    }

    static func counts(from windows: [[String: Any]]) -> [Int32: Int] {
        var result: [Int32: Int] = [:]
        for window in windows {
            guard let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  ((window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0.01,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let w = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let h = (bounds["Height"] as? NSNumber)?.doubleValue,
                  w >= minimumSide, h >= minimumSide else { continue }
            result[pid, default: 0] += 1
        }
        return result
    }
}
