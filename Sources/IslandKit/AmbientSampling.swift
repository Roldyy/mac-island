import Foundation
import IslandUI

/// Processor ticks summed over every core: `busy` is user + system + nice, `total` adds idle.
public struct CPUTicks: Equatable, Sendable {
    public var busy: UInt64
    public var total: UInt64

    public init(busy: UInt64, total: UInt64) {
        self.busy = busy
        self.total = total
    }
}

public enum MemoryPressure: Int, Sendable {
    case normal = 1, warning = 2, critical = 4

    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical. Anything else reads as normal.
    public init(level: Int) { self = MemoryPressure(rawValue: level) ?? .normal }

    public var status: IslandStatus {
        switch self {
        case .normal: .success
        case .warning: .warning
        case .critical: .danger
        }
    }

    public var word: String {
        switch self {
        case .normal: "normale"
        case .warning: "élevée"
        case .critical: "critique"
        }
    }
}

/// Byte counters of one network interface.
public struct InterfaceCounters: Equatable, Sendable {
    public var bytesIn: UInt64
    public var bytesOut: UInt64

    public init(bytesIn: UInt64, bytesOut: UInt64) {
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

/// What one pass of `getifaddrs` says about one interface, after its entries are merged.
public struct InterfaceReading: Equatable, Sendable {
    public var name: String
    /// Flags UP and RUNNING.
    public var isUp: Bool
    public var hasIPv4: Bool
    public var counters: InterfaceCounters?

    public init(name: String, isUp: Bool, hasIPv4: Bool, counters: InterfaceCounters?) {
        self.name = name
        self.isUp = isUp
        self.hasIPv4 = hasIPv4
        self.counters = counters
    }
}

public enum NetworkLink: Equatable, Sendable {
    case wifi, wired, other, offline
}

/// The arithmetic of the samplers, with no system call in it: counters in, numbers out.
public enum SamplingMath {
    // MARK: Processor

    /// Fraction of the interval the cores were busy, 0...1. Nil when no time passed or a counter went backwards
    /// (the first sample, a sleep that reset it).
    public static func cpuLoad(previous: CPUTicks, current: CPUTicks) -> Double? {
        guard current.total > previous.total, current.busy >= previous.busy else { return nil }
        let busy = Double(current.busy - previous.busy), total = Double(current.total - previous.total)
        return min(max(busy / total, 0), 1)
    }

    // MARK: Network

    /// Only real links count: `en0`, `en5`, ... Loopback, AirDrop (`awdl`), low latency WLAN (`llw`), the
    /// bridges and every `utun` are left out: a tunnel carries the same bytes the physical link already counted.
    public static func isPhysical(_ name: String) -> Bool {
        guard name.hasPrefix("en"), name.count > 2 else { return false }
        return name.dropFirst(2).allSatisfy(\.isNumber)
    }

    public static func isTunnel(_ name: String) -> Bool { name.hasPrefix("utun") }

    public static func counters(from readings: [InterfaceReading]) -> [String: InterfaceCounters] {
        var out: [String: InterfaceCounters] = [:]
        for reading in readings where reading.isUp && isPhysical(reading.name) {
            if let counters = reading.counters { out[reading.name] = counters }
        }
        return out
    }

    /// A VPN is a tunnel interface that is up and holds an IPv4 address (the system keeps IPv6 link-local
    /// `utun`s up all the time).
    public static func vpnActive(_ readings: [InterfaceReading]) -> Bool {
        readings.contains { isTunnel($0.name) && $0.isUp && $0.hasIPv4 }
    }

    private static let counterWrap: UInt64 = 1 << 32

    /// Bytes moved on every interface present in both samples. The counters of `getifaddrs` are 32 bits wide:
    /// a smaller value than before is a wrap, not a reset.
    public static func delta(previous: [String: InterfaceCounters], current: [String: InterfaceCounters]) -> InterfaceCounters {
        var total = InterfaceCounters(bytesIn: 0, bytesOut: 0)
        for (name, now) in current {
            guard let before = previous[name] else { continue }
            total.bytesIn += step(before.bytesIn, now.bytesIn)
            total.bytesOut += step(before.bytesOut, now.bytesOut)
        }
        return total
    }

    private static func step(_ before: UInt64, _ now: UInt64) -> UInt64 {
        if now >= before { return now - before }
        return before < counterWrap ? now + counterWrap - before : 0
    }

    /// Bytes per second down and up.
    public static func throughput(_ delta: InterfaceCounters, seconds: Double) -> (down: Double, up: Double) {
        guard seconds > 0, seconds.isFinite else { return (0, 0) }
        return (Double(delta.bytesIn) / seconds, Double(delta.bytesOut) / seconds)
    }
}

/// Pure builders of the indicators the samplers post: the same input gives equal indicators, so the center's
/// "unchanged" check stops a repost that shows the same thing.
public enum AmbientReadings {
    public static let clockID = "clock"
    public static let cpuID = "system.cpu"
    public static let memoryID = "system.mem"
    public static let linkID = "network.0link"
    public static let downID = "network.1down"
    public static let upID = "network.2up"
    public static let diskID = "disk"
    public static let micID = "mic"
    public static let cameraID = "camera"
    public static let volumeID = "volume"

    public static let networkIDs = [linkID, downID, upID]

    public static func clock(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current,
                             hours: ClockHours = .system) -> AmbientIndicator {
        AmbientIndicator(
            id: clockID, channel: AmbientChannel.clock, symbol: "clock",
            text: AmbientFormat.time(date, locale: locale, timeZone: timeZone, hours: hours),
            wing: .leading, glyph: .none, label: "Heure",
            detail: AmbientFormat.shortDate(date, timeZone: timeZone))
    }

    public static func cpu(load fraction: Double) -> AmbientIndicator {
        let shown = AmbientFormat.roundedPercent(fraction)
        return AmbientIndicator(
            id: cpuID, channel: AmbientChannel.system, symbol: "cpu", text: "\(shown)%",
            status: shown >= 90 ? .danger : shown >= 75 ? .warning : .neutral,
            label: "Processeur à \(shown) %")
    }

    public static func memory(usedBytes: UInt64, pressure: MemoryPressure) -> AmbientIndicator {
        let used = AmbientFormat.gigabytes(usedBytes)
        return AmbientIndicator(
            id: memoryID, channel: AmbientChannel.system, symbol: "circle.fill", text: used,
            status: pressure.status, label: "Mémoire utilisée \(used), pression \(pressure.word)")
    }

    public static func disk(freeBytes: UInt64) -> AmbientIndicator {
        let free = AmbientFormat.gigabytes(freeBytes)
        let go = Double(freeBytes) / 1e9
        return AmbientIndicator(
            id: diskID, channel: AmbientChannel.disk, symbol: "internaldrive", text: free,
            status: go < 5 ? .danger : go < 15 ? .warning : .neutral, label: "Espace disque libre \(free)")
    }

    /// The connection glyph (with a "VPN" tag while a tunnel is up), then the two rates. Offline: the glyph only.
    public static func network(link: NetworkLink, vpn: Bool, downBytesPerSecond: Double, upBytesPerSecond: Double) -> [AmbientIndicator] {
        let symbol: String
        switch link {
        case .wifi: symbol = "wifi"
        // The plain connector is a hairline at 14 pt; the horizontal one reads as an Ethernet plug.
        case .wired: symbol = "cable.connector.horizontal"
        case .other: symbol = "network"
        case .offline: symbol = "wifi.slash"
        }
        var out = [AmbientIndicator(
            id: linkID, channel: AmbientChannel.network, symbol: symbol, text: vpn ? "VPN" : nil,
            status: link == .offline ? .warning : vpn ? .info : .neutral,
            label: (link == .offline ? "Hors ligne" : "Connecté") + (vpn ? ", VPN actif" : ""))]
        guard link != .offline else { return out }
        let down = AmbientFormat.rate(downBytesPerSecond), up = AmbientFormat.rate(upBytesPerSecond)
        out.append(AmbientIndicator(
            id: downID, channel: AmbientChannel.network, symbol: "arrow.down", text: down, label: "Réception \(down)"))
        out.append(AmbientIndicator(
            id: upID, channel: AmbientChannel.network, symbol: "arrow.up", text: up, label: "Envoi \(up)"))
        return out
    }

    /// The strings the network indicators would show: what the sampler compares before it posts.
    public static func networkSignature(link: NetworkLink, vpn: Bool, down: Double, up: Double) -> String {
        network(link: link, vpn: vpn, downBytesPerSecond: down, upBytesPerSecond: up)
            .map { "\($0.symbol)|\($0.text ?? "")" }.joined(separator: ";")
    }

    /// Pinned (an `alert` priority) so an app listening is never rotated away, but without the urgent pulse.
    public static func mic() -> AmbientIndicator {
        AmbientIndicator(
            id: micID, channel: AmbientChannel.mic, symbol: "mic.fill", status: .warning, priority: .alert,
            label: "Micro utilisé par une application")
    }

    public static func camera() -> AmbientIndicator {
        AmbientIndicator(
            id: cameraID, channel: AmbientChannel.camera, symbol: "video.fill", status: .success, priority: .alert,
            label: "Caméra utilisée par une application")
    }

    public static func volume(level: Double, muted: Bool) -> AmbientIndicator {
        let clamped = min(max(level.isFinite ? level : 0, 0), 1)
        let percent = Int((clamped * 100).rounded())
        let symbol: String
        if muted || percent == 0 { symbol = "speaker.slash.fill" } else if percent < 34 { symbol = "speaker.wave.1.fill" } else if percent < 67 {
            symbol = "speaker.wave.2.fill"
        } else { symbol = "speaker.wave.3.fill" }
        return AmbientIndicator(
            id: volumeID, channel: AmbientChannel.volume, symbol: symbol, text: muted ? "Muet" : "\(percent)%",
            priority: .alert, label: muted ? "Volume coupé" : "Volume \(percent) %", bar: muted ? 0 : clamped)
    }
}
