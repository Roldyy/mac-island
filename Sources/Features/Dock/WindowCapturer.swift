import CoreGraphics
import Foundation
import ScreenCaptureKit

protocol WindowCapturing: Sendable {
    /// One image (or nil) per AX frame, same order. Needs Screen Recording; returns nils without it.
    func thumbnails(pid: Int32, frames: [CGRect], maxSize: CGSize) async -> [CGImage?]
}

/// ScreenCaptureKit: `SCScreenshotManager.captureImage(contentFilter:configuration:)`, macOS 14+ (checked in the SDK headers).
/// SCWindow frames use the same top-left global space as AX, so windows are matched by frame, no private window-id call.
struct SCKWindowCapturer: WindowCapturing {
    func thumbnails(pid: Int32, frames: [CGRect], maxSize: CGSize) async -> [CGImage?] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        else { return frames.map { _ in nil } }
        let candidates = content.windows.filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 }
        var result: [CGImage?] = []
        for frame in frames {
            guard let w = candidates.first(where: { Self.matches($0.frame, frame) }) else { result.append(nil); continue }
            let size = ThumbnailLimits.fit(w.frame.size, into: maxSize)
            guard size != .zero else { result.append(nil); continue }
            let config = SCStreamConfiguration()
            config.width = Int(size.width) * 2 // retina, still capped by maxSize
            config.height = Int(size.height) * 2
            config.showsCursor = false
            result.append(try? await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: config))
        }
        return result
    }

    static func matches(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 3) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
