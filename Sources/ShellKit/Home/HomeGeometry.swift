import CoreGraphics

/// Pure sizes of the open island, so the mapping "mode -> height" is testable without a view.
///
/// The panel is the black body plus the room the round buttons need: a column on each side and a row below.
public enum HomeGeometry {
    // Fixed pieces of the home body, top to bottom.
    static let slidersRow: CGFloat = 26
    static let nowPlayingCard: CGFloat = 64
    static let tileRow: CGFloat = 76
    static let gap: CGFloat = 8
    static let bottomPadding: CGFloat = 12
    /// Gap between the notch band and the sliders.
    static let bandGap: CGFloat = 6

    public static let compactWidth: CGFloat = 440
    public static let spaciousWidth: CGFloat = 532
    public static let customWidthRange: ClosedRange<Double> = 360...600
    public static let customHeightRange: ClosedRange<Double> = 260...640
    public static let defaultCustomWidth: Double = 440
    public static let defaultCustomHeight: Double = 480

    public static let maxTileRows = 3
    public static let tileColumns = 4

    /// Width of one round-button column, and height of the bottom row (circle + breathing room).
    public static let sideColumn: CGFloat = 64
    public static let bottomRow: CGFloat = 62
    public static let circleDiameter: CGFloat = 44

    /// Body width of a page opened from the island (terminal, Claude...): wide enough for the existing tabs.
    public static let pageBodyWidth: CGFloat = 592
    public static let exploreColumns = 5
    static let exploreRow: CGFloat = 78
    static let exploreHeader: CGFloat = 30

    /// Tile rows each mode shows. Custom fills the height the user allows, never beyond the tiles that exist.
    public static func tileRows(for mode: IslandSizeMode, customHeight: Double, band: CGFloat) -> Int {
        switch mode {
        case .compact: return 1
        case .spacious: return 2
        case .custom:
            let rows = Int(((CGFloat(customHeight) - fixedHeight(band: band)) / tileRow).rounded(.down))
            return min(max(rows, 1), maxTileRows)
        }
    }

    /// Everything but the tile rows.
    static func fixedHeight(band: CGFloat) -> CGFloat {
        band + bandGap + slidersRow + gap + nowPlayingCard + gap + bottomPadding
    }

    public static func homeBody(mode: IslandSizeMode, customWidth: Double, customHeight: Double, band: CGFloat) -> CGSize {
        let rows = tileRows(for: mode, customHeight: customHeight, band: band)
        let height = fixedHeight(band: band) + CGFloat(rows) * tileRow
        switch mode {
        case .compact: return CGSize(width: compactWidth, height: height)
        case .spacious: return CGSize(width: spaciousWidth, height: height)
        case .custom:
            let width = min(max(customWidth, customWidthRange.lowerBound), customWidthRange.upperBound)
            return CGSize(width: CGFloat(width), height: height)
        }
    }

    /// The Explorer grid keeps the home width and fits its rows.
    public static func exploreBody(home: CGSize, itemCount: Int, band: CGFloat) -> CGSize {
        let rows = max(1, min(4, (itemCount + exploreColumns - 1) / exploreColumns))
        return CGSize(width: home.width, height: band + exploreHeader + CGFloat(rows) * exploreRow + bottomPadding + gap)
    }

    /// A page keeps its own height (`ShellLayout.openHeight`); its header lives inside it.
    public static func pageBody(sectionHeight: CGFloat) -> CGSize {
        CGSize(width: pageBodyWidth, height: sectionHeight)
    }

    /// Panel = body + the room of the round buttons. Columns are symmetric (the panel stays centered on the notch).
    public static func panel(body: CGSize, sideButtons: Bool, bottomButtons: Bool) -> CGSize {
        CGSize(width: body.width + (sideButtons ? 2 * sideColumn : 0),
               height: body.height + (bottomButtons ? bottomRow : 0))
    }
}
