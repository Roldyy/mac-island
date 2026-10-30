import ApplicationServices
import CoreGraphics
import Foundation

/// Thin wrappers over the C Accessibility API. Compile-only in tests: they need the Accessibility permission.
enum AX {
    static func string(_ e: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }
    static func bool(_ e: AXUIElement, _ attr: String) -> Bool? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success else { return nil }
        return (v as? NSNumber)?.boolValue
    }
    static func url(_ e: AXUIElement) -> URL? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXURLAttribute as CFString, &v) == .success else { return nil }
        return (v as? NSURL) as URL?
    }
    static func elements(_ e: AXUIElement, _ attr: String) -> [AXUIElement] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success else { return [] }
        return (v as? [AXUIElement]) ?? []
    }
    /// Top-left origin, like every AX position.
    static func frame(_ e: AXUIElement) -> CGRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &s) == .success,
              let p, let s, CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: point, size: size)
    }
    static func set(_ e: AXUIElement, _ attr: String, _ value: Bool) {
        AXUIElementSetAttributeValue(e, attr as CFString, value as CFBoolean)
    }
}

/// AX uses a top-left origin on the primary screen, AppKit a bottom-left one.
enum CoordinateFlip {
    static func cocoa(fromAX r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
    static func ax(fromCocoa p: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }
}
