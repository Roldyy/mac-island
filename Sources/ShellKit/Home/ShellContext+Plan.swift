import CoreGraphics

/// What size the open island needs for the page it shows. Pure reads, so the app and the tests share it.
@MainActor
extension ShellContext {
    /// Tab ids of every feature panel, grouped ones first (the Explorer's tiles are `tileItems(showHidden:)`).
    public var exploreTabIDs: [String] {
        ShellLayout.exploreTabIDs(available: tabs.map(\.id)) { _ in true }
    }

    /// Size of the black body for the current route.
    public var bodySize: CGSize {
        let band = home.bandHeight
        switch navigation.route {
        case .home:
            return home.homeBody(tileCount: tileItems().count)
        case .explore:
            // The Explorer lists the same tiles as the home (hidden ones too) at the home's width and columns.
            return HomeGeometry.exploreBody(home: home.homeBody, itemCount: tileItems(showHidden: true).count,
                                            columns: home.tileColumns, band: band)
        case .page(let id):
            return HomeGeometry.pageBody(sectionHeight: ShellLayout.openHeight(forSection: id))
        }
    }

    /// Size of the whole panel: the body plus the room the round buttons need.
    public var panelSize: CGSize { home.panelSize(body: bodySize) }
}
