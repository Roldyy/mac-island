import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The cover as stored with the last track: JPEG, at most 256 px on the long edge, small enough for a tiny file.
enum LastTrackThumbnail {
    static let maxPixels = 256
    static let maxBytes = 200 * 1024
    static let quality = 0.7

    /// Nil when the data is not an image or the result is still too big (the track is kept without a cover).
    static func jpeg(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination), out.length <= maxBytes else { return nil }
        return out as Data
    }
}
