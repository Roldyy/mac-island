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
