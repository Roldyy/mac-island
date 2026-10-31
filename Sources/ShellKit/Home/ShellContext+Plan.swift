import CoreGraphics

/// What size the open island needs for the page it shows. Pure reads, so the app and the tests share it.
@MainActor
extension ShellContext {
    /// Tab ids the Explorer lists: every enabled feature panel, grouped ones first.
    public var exploreTabIDs: [String] {
        ShellLayout.exploreTabIDs(available: tabs.map(\.id)) { registry.isEnabled($0) }
    }

    /// Size of the black body for the current route.
    public var bodySize: CGSize {
        let band = home.bandHeight
        switch navigation.route {
        case .home:
            return home.homeBody
        case .explore:
            return HomeGeometry.exploreBody(home: home.homeBody, itemCount: exploreTabIDs.count, band: band)
        case .page(let id):
            return HomeGeometry.pageBody(sectionHeight: ShellLayout.openHeight(forSection: id))
        }
    }

    /// Size of the whole panel: the body plus the room the round buttons need.
    public var panelSize: CGSize { home.panelSize(body: bodySize) }
}
