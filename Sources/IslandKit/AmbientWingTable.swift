import Foundation

/// Which wing each channel lives on, and in which order inside it. Pure and fixed: the user's order (Settings)
/// still ranks channels of the same priority, this table only decides the side and the default order.
///
/// - Left: Claude first (working, waiting, the plan limits), then music, then the network.
/// - Center: the clock, always (on a screen with a hardware notch the centre is the notch, so the clock is
///   the innermost item of the left wing there).
/// - Right: the battery first, then the keep-awake cup, then the system (processor, memory), the mic, the
///   camera, the disk and the volume.
/// Alerts have no fixed side: they take the wing with room (`AmbientIndicator.wing` is only their preference).
public enum AmbientWingTable {
    public static let leading: [String] = [
        AmbientChannel.claude, AmbientChannel.limits, AmbientChannel.music, AmbientChannel.network,
    ]
    public static let trailing: [String] = [
        AmbientChannel.battery, AmbientChannel.keepAwake, AmbientChannel.system, AmbientChannel.mic,
        AmbientChannel.camera, AmbientChannel.disk, AmbientChannel.volume,
    ]

    /// nil for the clock and the alerts.
    public static func wing(for channel: String) -> AmbientWing? {
        if leading.contains(channel) { return .leading }
        if trailing.contains(channel) { return .trailing }
        return nil
    }

    /// Position inside the wing; channels outside the table come last.
    public static func rank(_ channel: String) -> Int {
        leading.firstIndex(of: channel) ?? trailing.firstIndex(of: channel) ?? (leading.count + trailing.count)
    }
}
