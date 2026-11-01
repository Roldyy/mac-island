import Foundation

/// A command another feature hands to the bar through `CommandBarFeature.register(commands:)`.
public struct BarCommand {
    public let id: String
    public let title: String
    public let keywords: [String]
    public let run: @MainActor () -> Void

    public init(id: String, title: String, keywords: [String] = [], run: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.keywords = keywords
        self.run = run
    }
}
