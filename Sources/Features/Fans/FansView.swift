import IslandKit
import SwiftUI

/// The tab: read-only monitoring on top, manual control below, separated and gated.
/// Black island, system font, nothing happens on hover.
struct FansView: View {
    @Bindable var model: FansModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MonitoringSection(model: model)
                Divider().overlay(Color.white.opacity(0.15))
                ManualControlSection(model: model)
                if let message = model.statusMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .task {
            await model.appeared()
            await model.monitor()
        }
        .onDisappear {
            Task { await model.viewClosed() }
        }
    }
}
