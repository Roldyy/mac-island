import PortKit
import SwiftUI

/// The tab: shelf and downloads segments. Black island, system font, no hover side effects
/// (nothing here ever asks for the keyboard). The Étagère segment is the ported shelf's strip.
struct ShelfView: View {
    @Bindable var model: ShelfModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Section", selection: $model.segment) {
                ForEach(ShelfSegment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Section de l'étagère")

            switch model.segment {
            case .shelf: PortShelf.strip()
            case .downloads: DownloadsPane(model: model)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .task { model.start() }
    }
}
