import CoreGraphics
import Foundation

/// Counts layer-0 windows per owner pid, in any state: minimized, on another Space, full screen
/// elsewhere and windows of a hidden app all count. "On screen only" would make those apps look
/// windowless. Needs no Screen Recording permission (window titles are never read).
enum WindowCounter {
    static let minimumSide: Double = 8

    /// Source of the window list, so the options passed to the system are testable.
    typealias WindowLister = (CGWindowListOption, CGWindowID) -> [[String: Any]]

    static let systemLister: WindowLister = { options, relativeTo in
        (CGWindowListCopyWindowInfo(options, relativeTo) as? [[String: Any]]) ?? []
    }

    static func currentCounts(lister: WindowLister = systemLister) -> [Int32: Int] {
        counts(from: lister([.optionAll, .excludeDesktopElements], kCGNullWindowID))
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
