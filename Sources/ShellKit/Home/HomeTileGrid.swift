import IslandUI
import SwiftUI

/// The tile grid shared by the home and the Explorer. Shows `visibleRows` rows; when there are more tiles it
/// becomes a lazy vertical scroll (rows snap, scroll bar on hover, edges fade where more tiles hide), so the
/// island keeps its height whatever the number of tiles.
struct HomeTileGrid: View {
    let items: [HomeTileItem]
    let columns: Int
    let visibleRows: Int
    let context: ShellContext

    @State private var hovering = false
    /// Row at the top of the viewport, kept by the scroll view itself (rows are the scroll targets).
    @State private var topRow: Int? = 0

    private static let fade: CGFloat = 20

    var body: some View {
        let rows = HomeTileCatalog.rows(items, columns: columns)
        let height = CGFloat(visibleRows) * HomeGeometry.tileRow
        if rows.count <= visibleRows {
            VStack(spacing: 0) { rowViews(rows) }
                .frame(height: height, alignment: .top)
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) { rowViews(rows) }
                    .scrollTargetLayout()
            }
            .scrollPosition(id: $topRow)
            .scrollIndicators(hovering ? .automatic : .hidden)
            .scrollTargetBehavior(.viewAligned)
            .frame(height: height)
            .mask(fadeMask(height: height, edges: HomeGeometry.hiddenEdges(
                topRow: topRow ?? 0, visibleRows: visibleRows, totalRows: rows.count)))
            .onHover { hovering = $0 }
            .accessibilityLabel("Raccourcis")
            .accessibilityHint("Fais défiler pour voir les autres raccourcis")
        }
    }

    @ViewBuilder private func rowViews(_ rows: [[HomeTileItem]]) -> some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            HStack(spacing: 0) {
                ForEach(row) { HomeTile(item: $0, context: context) }
                ForEach(0..<(columns - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
            }
            .frame(height: HomeGeometry.tileRow)
        }
    }

    /// Opaque in the middle; the top and bottom edges fade only where tiles are hidden beyond them.
    private func fadeMask(height: CGFloat, edges: (above: Bool, below: Bool)) -> some View {
        let edge = Self.fade / height
        return LinearGradient(stops: [
            .init(color: .black.opacity(edges.above ? 0 : 1), location: 0),
            .init(color: .black, location: edge),
            .init(color: .black, location: 1 - edge),
            .init(color: .black.opacity(edges.below ? 0 : 1), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }
}
