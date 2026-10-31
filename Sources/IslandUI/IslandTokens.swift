import SwiftUI

/// Type scale. Nothing in the app is smaller than `minimumSize`.
public enum IslandType {
    public static let minimumSize: CGFloat = 11
    public static let body: CGFloat = 13
    public static let caption: CGFloat = 12
    public static let footnote: CGFloat = 11
}

public extension Font {
    static let islandBody = Font.system(size: IslandType.body)
    static let islandBodyEmphasis = Font.system(size: IslandType.body, weight: .semibold)
    static let islandCaption = Font.system(size: IslandType.caption)
    static let islandCaptionEmphasis = Font.system(size: IslandType.caption, weight: .medium)
    static let islandFootnote = Font.system(size: IslandType.footnote)
    static let islandValue = Font.system(size: IslandType.caption, weight: .medium).monospacedDigit()
}

public enum IslandSpacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
}

public enum IslandRadius {
    public static let small: CGFloat = 6
    public static let medium: CGFloat = 10
    public static let large: CGFloat = 14
}

public enum IslandMetrics {
    public static let controlHeight: CGFloat = 26
    public static let hudBarHeight: CGFloat = 6
    public static let switchSize = CGSize(width: 38, height: 22)
}
