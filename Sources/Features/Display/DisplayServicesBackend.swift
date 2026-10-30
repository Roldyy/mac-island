import CoreGraphics
import Darwin
import Foundation

/// Brightness of the built-in display through the private DisplayServices framework.
/// The framework is loaded at runtime (never linked) and the two symbols are resolved with
/// dlsym; when either is missing, or no built-in display exists, `read()` returns nil and the
/// tab shows "indisponible". External displays (DDC) are out of scope.
final class DisplayServicesBackend: BrightnessBackend, @unchecked Sendable {
    private typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (UInt32, Float) -> Int32

    private static let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
    private let getFn: GetFn?
    private let setFn: SetFn?

    init() {
        if let handle = dlopen(Self.path, RTLD_LAZY) {
            getFn = dlsym(handle, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetFn.self) }
            setFn = dlsym(handle, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetFn.self) }
        } else {
            getFn = nil
            setFn = nil
        }
    }

    /// First active built-in display, nil on a desktop Mac or when none is attached.
    static func builtInDisplayID() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    func read() -> Float? {
        guard let getFn, let id = Self.builtInDisplayID() else { return nil }
        var value: Float = 0
        guard getFn(id, &value) == 0, value.isFinite else { return nil }
        return min(1, max(0, value))
    }

    func write(_ value: Float) -> Bool {
        guard let setFn, let id = Self.builtInDisplayID() else { return false }
        return setFn(id, min(1, max(0, value))) == 0
    }
}
