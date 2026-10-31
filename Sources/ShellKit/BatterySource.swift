import Foundation
import IOKit.ps
import IslandKit

/// Keeps the battery indicator current. Event driven: IOKit calls back on the main run loop whenever the
/// power source changes (level, charger, estimate), so nothing polls. The center ignores a repost that
/// changes nothing, so a chatty notification costs one comparison.
///
/// The run-loop source holds an unretained pointer to this object: keep it alive (the app delegate does) and
/// call `stop()` before releasing it.
@MainActor
public final class BatterySource {
    public static let indicatorID = BatteryReading.indicatorID

    private let center: AmbientCenter
    private let read: () -> BatteryReading?
    private var runLoopSource: CFRunLoopSource?

    public init(center: AmbientCenter, read: @escaping () -> BatteryReading? = { BatteryReading.current() }) {
        self.center = center
        self.read = read
    }

    public func start() {
        guard runLoopSource == nil else { return }
        refresh()
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let owner = Unmanaged<BatterySource>.fromOpaque(context).takeUnretainedValue()
            // The source is attached to the main run loop, so this runs on the main thread.
            MainActor.assumeIsolated { owner.refresh() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
    }

    public func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        center.withdraw(id: Self.indicatorID)
    }

    /// Reads once and posts, or withdraws when there is no battery (a desktop Mac).
    public func refresh() {
        if let reading = read() { center.post(reading.indicator) } else { center.withdraw(id: Self.indicatorID) }
    }
}
