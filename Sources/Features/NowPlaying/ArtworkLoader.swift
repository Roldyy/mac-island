import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Seam for the cover download, so tests can race a slow fetch against a fast one.
protocol ArtworkLoading: Sendable {
    func artwork(for snap: NowPlayingSnapshot) async -> Data?
}

/// Loads cover art off the main thread, caps byte size and pixel size, caches in memory.
/// Returns PNG data of at most `maxPixels` on the long edge.
actor ArtworkLoader: ArtworkLoading {
    static let maxBytes = 4 * 1024 * 1024
    static let maxPixels = 320

    private var cache: [String: Data] = [:]
    private var order: [String] = []
    private let limit = 24
    private let fetch: @Sendable (URL) async throws -> Data

    init(fetch: @escaping @Sendable (URL) async throws -> Data = { url in
        try await URLSession.shared.data(from: url).0
    }) {
        self.fetch = fetch
    }

    func artwork(for snap: NowPlayingSnapshot) async -> Data? {
        if let hit = cache[snap.trackKey] { return hit }
        var raw = snap.artworkData
        if raw == nil, let url = snap.artworkURL { raw = try? await fetch(url) }
        guard let raw, raw.count <= Self.maxBytes, let small = Self.downsample(raw) else { return nil }
        store(small, key: snap.trackKey)
        return small
    }

    private func store(_ d: Data, key: String) {
        cache[key] = d
        order.append(key)
        if order.count > limit { cache[order.removeFirst()] = nil }
    }

    static func downsample(_ data: Data) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, img, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}
