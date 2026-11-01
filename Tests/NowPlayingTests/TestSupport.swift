import Foundation
@testable import NowPlayingFeature

func snap(_ bundle: String, title: String = "T", playing: Bool, position: TimeInterval = 10,
          duration: TimeInterval = 100) -> NowPlayingSnapshot {
    NowPlayingSnapshot(title: title, artist: "A", album: "Al", artworkURL: nil, artworkData: nil,
                       isPlaying: playing, position: position, duration: duration, sourceBundleID: bundle)
}

final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ v: T) { value = v }
    func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ v: T) { lock.lock(); value = v; lock.unlock() }
}

final class FakeProvider: NowPlayingProvider, @unchecked Sendable {
    let bundleID: String
    let result: Box<Result<NowPlayingSnapshot?, NowPlayingError>>
    let calls = Box(0)
    init(_ id: String, _ r: Result<NowPlayingSnapshot?, NowPlayingError>) {
        bundleID = id; result = Box(r)
    }
    func snapshot() async throws -> NowPlayingSnapshot? {
        calls.set(calls.get() + 1)
        return try result.get().get()
    }
}

/// Cover loader with a per-title delay; the returned bytes name the title.
final class FakeLoader: ArtworkLoading, @unchecked Sendable {
    private let delays: [String: Duration]
    let calls = Box<[String]>([])
    init(delays: [String: Duration]) { self.delays = delays }
    func artwork(for snap: NowPlayingSnapshot) async -> Data? {
        calls.set(calls.get() + [snap.title])
        if let d = delays[snap.title] { try? await Task.sleep(for: d) }
        return Data(snap.title.utf8)
    }
}

/// In-memory flag store: nothing is ever written to ~/Library/Preferences.
final class MemoryFlags: NowPlayingFlagStore {
    private var values: [String: Bool] = [:]
    func bool(forKey key: String) -> Bool { values[key] ?? false }
    func set(_ value: Bool, forKey key: String) { values[key] = value }
}

@MainActor
/// Load tolerant: a failing wait needs BOTH `timeout` of wall clock AND `minimumPolls` turns, so other main-actor
/// tests holding the main thread cannot expire the deadline before the code under test got a turn.
func eventually(timeout: TimeInterval = 10, minimumPolls: Int = 300, _ condition: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    var polls = 0
    while polls < minimumPolls || Date() < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
        polls += 1
    }
    return condition()
}
