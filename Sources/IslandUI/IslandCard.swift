import SwiftUI

/// A glass container with the standard padding.
public struct IslandCard<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content
            .padding(IslandSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .islandGlass(cornerRadius: IslandRadius.medium)
    }
}
