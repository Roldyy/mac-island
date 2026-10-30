import Foundation

/// One history item. The JSON shape is the one the Vorssaint app wrote (observed keys:
/// id, kind, text, filePaths, sourceBundleID, copiedAt, imageFile, imageHash, imageWidth,
/// imageHeight). `copiedAt` is seconds since 2001 (Swift's default Date encoding).
/// `pinned` is new; absent in migrated files and read as false. Unknown keys are ignored.
struct ClipboardEntry: Identifiable, Equatable, Sendable, Codable {
    enum Kind: String, Sendable { case text, image, files }

    var id: String
    var kind: Kind
    var text: String
    var filePaths: [String]
    var sourceBundleID: String?
    var copiedAt: Date
    var imageFile: String?
    var imageHash: String?
    var imageWidth: Int?
    var imageHeight: Int?
    var pinned: Bool

    init(id: String = UUID().uuidString, kind: Kind, text: String = "", filePaths: [String] = [],
         sourceBundleID: String? = nil, copiedAt: Date, imageFile: String? = nil,
         imageHash: String? = nil, imageWidth: Int? = nil, imageHeight: Int? = nil, pinned: Bool = false) {
        self.id = id; self.kind = kind; self.text = text; self.filePaths = filePaths
        self.sourceBundleID = sourceBundleID; self.copiedAt = copiedAt; self.imageFile = imageFile
        self.imageHash = imageHash; self.imageWidth = imageWidth; self.imageHeight = imageHeight
        self.pinned = pinned
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, text, filePaths, sourceBundleID, copiedAt
        case imageFile, imageHash, imageWidth, imageHeight, pinned
    }

    /// A file name that stays inside the images folder.
    static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = try c.decode(String.self, forKey: .kind)
        guard let kind = Kind(rawValue: rawKind) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown kind")
        }
        self.kind = kind
        self.id = ((try? c.decodeIfPresent(String.self, forKey: .id)) ?? nil) ?? UUID().uuidString
        self.text = ((try? c.decodeIfPresent(String.self, forKey: .text)) ?? nil) ?? ""
        self.filePaths = ((try? c.decodeIfPresent([String].self, forKey: .filePaths)) ?? nil) ?? []
        self.sourceBundleID = (try? c.decodeIfPresent(String.self, forKey: .sourceBundleID)) ?? nil
        let seconds = try c.decode(Double.self, forKey: .copiedAt)
        self.copiedAt = Date(timeIntervalSinceReferenceDate: seconds)
        self.imageFile = (try? c.decodeIfPresent(String.self, forKey: .imageFile)) ?? nil
        self.imageHash = (try? c.decodeIfPresent(String.self, forKey: .imageHash)) ?? nil
        self.imageWidth = (try? c.decodeIfPresent(Int.self, forKey: .imageWidth)) ?? nil
        self.imageHeight = (try? c.decodeIfPresent(Int.self, forKey: .imageHeight)) ?? nil
        self.pinned = ((try? c.decodeIfPresent(Bool.self, forKey: .pinned)) ?? nil) ?? false

        // An entry that cannot be shown or restored is skipped by the lossy loader.
        func invalid(_ why: String) -> DecodingError {
            .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: why))
        }
        switch kind {
        case .text where text.isEmpty: throw invalid("empty text")
        case .files where filePaths.isEmpty: throw invalid("no files")
        case .image:
            guard let f = imageFile, Self.isSafeFileName(f) else { throw invalid("bad image file") }
        default: break
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind.rawValue, forKey: .kind)
        try c.encode(text, forKey: .text)
        try c.encode(filePaths, forKey: .filePaths)
        try c.encodeIfPresent(sourceBundleID, forKey: .sourceBundleID)
        try c.encode(copiedAt.timeIntervalSinceReferenceDate, forKey: .copiedAt)
        try c.encodeIfPresent(imageFile, forKey: .imageFile)
        try c.encodeIfPresent(imageHash, forKey: .imageHash)
        try c.encodeIfPresent(imageWidth, forKey: .imageWidth)
        try c.encodeIfPresent(imageHeight, forKey: .imageHeight)
        try c.encode(pinned, forKey: .pinned)
    }
}
