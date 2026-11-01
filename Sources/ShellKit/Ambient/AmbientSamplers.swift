import IslandKit

/// The samplers the app runs for the closed island, one per channel. The battery and keep-awake sources are
/// event driven and cheap, they predate the hub and stay wired by the app delegate.
@MainActor
public enum AmbientSamplers {
    public static func standard(center: AmbientCenter) -> [any AmbientSampler] {
        [
            ClockSampler(center: center),
            SystemSampler(center: center),
            NetworkSampler(center: center),
            DiskSampler(center: center),
            MicSampler(center: center),
            CameraSampler(center: center),
            VolumeSampler(center: center),
        ]
    }
}
