import SwiftUI

struct PreviewView: View {
    let model: PreviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.needsScreenRecording {
                HStack(spacing: 8) {
                    Text(PermissionLines.screenRecording(granted: false))
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Allow", action: model.onRequestScreenRecording)
                        .controlSize(.small)
                        .accessibilityHint("Opens the system Screen Recording prompt")
                }
            }
            HStack(spacing: 10) {
                ForEach(model.items) { item in
                    Button { model.onRaise(item.id) } label: {
                        VStack(spacing: 4) {
                            thumbnail(item)
                            Text(item.title.isEmpty ? model.appName : item.title)
                                .font(.caption2).lineLimit(1)
                                .frame(width: ThumbnailLimits.maxSize.width)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(model.appName) window \(item.id + 1)\(item.title.isEmpty ? "" : ", \(item.title)")")
                    .accessibilityHint("Brings this window to the front")
                }
            }
        }
        .padding(10)
        .foregroundStyle(.white)
        .background(.black, in: RoundedRectangle(cornerRadius: 14))
        .fixedSize()
    }

    @ViewBuilder private func thumbnail(_ item: PreviewItem) -> some View {
        let box = ThumbnailLimits.maxSize
        if let image = item.thumbnail {
            Image(decorative: image, scale: 2)
                .resizable().scaledToFit()
                .frame(maxWidth: box.width, maxHeight: box.height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .opacity(item.isMinimized ? 0.6 : 1)
        } else {
            RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.1))
                .frame(width: box.width, height: 40)
                .overlay(Image(systemName: "macwindow").foregroundStyle(.secondary))
        }
    }
}
