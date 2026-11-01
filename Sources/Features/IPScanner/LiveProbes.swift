import Darwin
import Foundation

// Live implementations of the scan doors. None of them runs in a test (the tests use fakes).

/// Nudge = one TCP connect to the discard port. Whatever the answer, the system had to resolve the address first,
/// which is what puts the host in the ARP table; a refusal or a connection also gives the latency.
public struct TCPHostNudger: HostNudging {
    public static let nudgePort: UInt16 = 7
    public init() {}

    public func nudge(_ ip: IPv4Address, timeout: Duration) async -> NudgeOutcome {
        switch await TCPConnector.connect(to: ip, port: Self.nudgePort, timeout: timeout) {
        case .open(let ms), .refused(let ms): .answered(latencyMs: ms)
        default: .silent
        }
    }
}

public struct TCPPortProber: PortProbing {
    public init() {}

    public func isOpen(host: IPv4Address, port: UInt16, timeout: Duration) async -> Bool {
        if case .open = await TCPConnector.connect(to: host, port: port, timeout: timeout) { return true }
        return false
    }
}

public struct SystemLocalNetworkChecker: LocalNetworkChecking {
    public init() {}

    public func check(target: IPv4Address) async -> LocalNetworkState {
        LocalNetworkClassifier.state(after: await TCPConnector.connect(to: target, port: 80, timeout: .seconds(2)))
    }
}

/// `getnameinfo` with a hard bound: the call blocks, so it runs on a background queue and the caller stops waiting
/// at `timeout` whatever it does.
public struct SystemNameResolver: NameResolving {
    public let timeout: Duration
    public init(timeout: Duration = .milliseconds(1500)) { self.timeout = timeout }

    public func hostName(for ip: IPv4Address) async -> String? {
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let once = OnceResume(continuation)
            DispatchQueue.global(qos: .utility).async { once.resume(Self.lookup(ip)) }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds) { once.resume(nil) }
        }
    }

    static func lookup(_ ip: IPv4Address) -> String? {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = ip.value.bigEndian
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size), &buffer, socklen_t(buffer.count), nil, 0, NI_NAMEREQD)
            }
        }
        guard status == 0 else { return nil }
        return DisplayText.clean(String(cString: buffer))
    }
}

/// Resumes a continuation exactly once, from whichever of two racing callbacks gets there first.
final class OnceResume<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?
    init(_ continuation: CheckedContinuation<T, Never>) { self.continuation = continuation }

    func resume(_ value: T) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

/// Runs a fixed program: absolute path, argument array, no shell, a minimal environment, no standard input, the
/// output cut at `maxBytes` and the whole run cut at `timeout`.
public struct FixedArgvRunner: ArgvRunning {
    public init() {}

    public func run(path: String, arguments: [String], maxBytes: Int, timeout: Duration) async -> Data? {
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        return await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            let once = OnceResume(continuation)
            DispatchQueue.global(qos: .utility).async { once.resume(Self.runBlocking(path, arguments, maxBytes, seconds)) }
        }
    }

    private static func runBlocking(_ path: String, _ arguments: [String], _ maxBytes: Int, _ seconds: Double) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        do { try process.run() } catch { return nil }
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: killer)
        var data = Data()
        while data.count < maxBytes {
            guard let chunk = try? pipe.fileHandleForReading.read(upToCount: min(16_384, maxBytes - data.count)), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        if data.count >= maxBytes, process.isRunning { process.terminate() }
        process.waitUntilExit()
        killer.cancel()
        return process.terminationStatus == 0 ? data : nil
    }
}

/// The neighbour table from `/usr/sbin/arp -an`: fixed program, fixed arguments, strict bounded parsing.
public struct ArpTableReader: NeighborTableReading {
    public static let executable = "/usr/sbin/arp"
    public static let arguments = ["-an"]

    private let runner: any ArgvRunning
    public init(runner: any ArgvRunning = FixedArgvRunner()) { self.runner = runner }

    public func read() async -> [ArpEntry] {
        guard let data = await runner.run(path: Self.executable, arguments: Self.arguments,
                                          maxBytes: ArpParser.maxBytes, timeout: .seconds(3)) else { return [] }
        return ArpParser.parse(data)
    }
}

/// The opt-in public IP lookup: ONE GET to one URL the user can read on the button, no cookies, no cache, a tiny
/// bounded answer that must be an IP literal.
public struct URLSessionPublicIPFetcher: PublicIPFetching {
    public init() {}

    public func fetch(from url: URL) async throws -> String {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return String(decoding: data.prefix(PublicIPLookup.maxResponseBytes), as: UTF8.self)
    }
}
