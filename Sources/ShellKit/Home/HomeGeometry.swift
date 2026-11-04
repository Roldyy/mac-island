import CoreGraphics

/// Pure sizes of the open island, so the mapping "mode -> height" is testable without a view.
///
/// The panel is the black body plus the room the round buttons need: a column on each side and a row below.
public enum HomeGeometry {
    // Fixed pieces of the home body, top to bottom.
    static let slidersRow: CGFloat = 26
    static let nowPlayingCard: CGFloat = 64
    /// One tile row of the home grid and of the Explorer (same component, same height).
    static let tileRow: CGFloat = 64
    static let gap: CGFloat = 8
    /// The extra dock: one pinned row between the now-playing card and the grid (buttons 34 pt + breathing room).
    /// Its height and the gap above it are `extraDockSpace`; the bottom row of the round buttons is untouched.
    public static let extraDockRow: CGFloat = 40
    public static let extraDockSpace: CGFloat = extraDockRow + gap
    /// The status chips: one pinned row of capsules between the now-playing card and the extra dock. Like the dock,
    /// its height and the gap above it are `statusChipSpace`, counted only while the row has a slot.
    public static let statusChipRow: CGFloat = 30
    public static let statusChipSpace: CGFloat = statusChipRow + gap
    static let bottomPadding: CGFloat = 12
    /// Gap between the notch band and the sliders.
    static let bandGap: CGFloat = 6

    public static let compactWidth: CGFloat = 440
    public static let spaciousWidth: CGFloat = 532
    public static let customWidthRange: ClosedRange<Double> = 360...600
    public static let customHeightRange: ClosedRange<Double> = 260...640
    public static let defaultCustomWidth: Double = 440
    public static let defaultCustomHeight: Double = 480

    /// Rows the grid shows at once: Compacte 2, Spacieuse 3, Personnalisé as many as its height allows up to 6.
    /// Beyond them the grid scrolls under the pinned sliders and now-playing card, so the island stays bounded.
    public static let compactTileRows = 2
    public static let spaciousTileRows = 3
    public static let maxTileRows = 6
    /// Columns: 4 when the island is narrow (Compacte, or a custom width under `fiveColumnWidth`), otherwise 5.
    public static let fiveColumnWidth: Double = 500
    /// Rows the Explorer shows before it scrolls.
    public static let maxExploreRows = 4

    /// Width of one round-button column, and height of the bottom row (circle + breathing room).
    public static let sideColumn: CGFloat = 64
    public static let bottomRow: CGFloat = 62
    public static let circleDiameter: CGFloat = 44

    /// Body width of a page opened from the island (terminal, Claude...): wide enough for the existing tabs.
    public static let pageBodyWidth: CGFloat = 592
    static let exploreHeader: CGFloat = 30

    public static func tileColumns(for mode: IslandSizeMode, width: Double) -> Int {
        switch mode {
        case .compact: 4
        case .spacious: 5
        case .custom: width >= fiveColumnWidth ? 5 : 4
        }
    }

    /// The most tile rows a mode shows. Custom fills the height the user allows.
    public static func tileRows(for mode: IslandSizeMode, customHeight: Double, band: CGFloat, dock: CGFloat = 0,
                                status: CGFloat = 0) -> Int {
        switch mode {
        case .compact: return compactTileRows
        case .spacious: return spaciousTileRows
        case .custom:
            let rows = Int(((CGFloat(customHeight) - fixedHeight(band: band, dock: dock, status: status)) / tileRow).rounded(.down))
            return min(max(rows, 1), maxTileRows)
        }
    }

    /// Rows needed for `count` tiles in `columns` columns (never overflows, whatever the count).
    static func rowsNeeded(count: Int, columns: Int) -> Int {
        guard count > 0, columns > 0 else { return 0 }
        return count / columns + (count % columns == 0 ? 0 : 1)
    }

    /// Rows the home really shows: the mode's cap, but no empty rows when there are few tiles.
    public static func visibleTileRows(for mode: IslandSizeMode, customWidth: Double, customHeight: Double,
                                       band: CGFloat, tileCount: Int, dock: CGFloat = 0, status: CGFloat = 0) -> Int {
        let cap = tileRows(for: mode, customHeight: customHeight, band: band, dock: dock, status: status)
        let needed = rowsNeeded(count: tileCount, columns: tileColumns(for: mode, width: customWidth))
        return min(cap, max(needed, 1))
    }

    /// Everything but the tile rows.
    /// `dock` is `extraDockSpace` while the extra dock shows, otherwise 0; `status` is `statusChipSpace` while the
    /// status chip row has a slot, otherwise 0.
    static func fixedHeight(band: CGFloat, dock: CGFloat = 0, status: CGFloat = 0) -> CGFloat {
        band + bandGap + slidersRow + gap + nowPlayingCard + status + dock + gap + bottomPadding
    }

    public static func homeBody(mode: IslandSizeMode, customWidth: Double, customHeight: Double, band: CGFloat,
                                tileCount: Int = .max, dock: CGFloat = 0, status: CGFloat = 0) -> CGSize {
        let rows = visibleTileRows(for: mode, customWidth: customWidth, customHeight: customHeight, band: band,
                                   tileCount: tileCount, dock: dock, status: status)
        let height = fixedHeight(band: band, dock: dock, status: status) + CGFloat(rows) * tileRow
        switch mode {
        case .compact: return CGSize(width: compactWidth, height: height)
        case .spacious: return CGSize(width: spaciousWidth, height: height)
        case .custom:
            let width = min(max(customWidth, customWidthRange.lowerBound), customWidthRange.upperBound)
            return CGSize(width: CGFloat(width), height: height)
        }
    }

    /// Which edges of a scrolling grid hide more rows: the top one when the first visible row is not row 0, the
    /// bottom one while rows remain below the visible ones. These are the edges that fade.
    static func hiddenEdges(topRow: Int, visibleRows: Int, totalRows: Int) -> (above: Bool, below: Bool) {
        (topRow > 0, topRow + visibleRows < totalRows)
    }

    /// Rows the Explorer shows: all of them up to `maxExploreRows`, then it scrolls.
    public static func exploreRows(itemCount: Int, columns: Int) -> Int {
        max(1, min(maxExploreRows, rowsNeeded(count: itemCount, columns: columns)))
    }

    /// The Explorer grid keeps the home width and fits its rows.
    public static func exploreBody(home: CGSize, itemCount: Int, columns: Int, band: CGFloat) -> CGSize {
        let rows = exploreRows(itemCount: itemCount, columns: columns)
        return CGSize(width: home.width, height: band + exploreHeader + CGFloat(rows) * tileRow + bottomPadding + gap)
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
