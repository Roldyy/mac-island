import IslandUI
import SwiftUI

/// Six buttons at the bottom of the open island. A button whose action is not registered stays dimmed.
struct QuickAccessBar: View {
    let model: QuickAccessModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(model.items) { item in
                let available = model.table.isAvailable(item.id)
                Button { model.table.fire(item.id) } label: {
                    Label(item.shortTitle, systemImage: item.systemImage)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(IslandButtonStyle())
                .disabled(!available)
                .opacity(available ? 1 : 0.4)
                .help(available ? item.title : "\(item.title) : pas encore disponible")
                .accessibilityLabel(item.title)
            }
        }
    }
}
