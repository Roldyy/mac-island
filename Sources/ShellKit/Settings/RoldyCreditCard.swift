import AppKit
import IslandUI
import SwiftUI

/// Where the Roldy Management credit points: one place for the URL and the line, shared by About, Support and Nouveautés.
enum RoldyBrand {
    static let websiteHost = "www.roldymanagement.be"
    static let websiteURL = URL(string: "https://\(websiteHost)")!
    /// The ÿ is part of the name.
    static let creditLine = "Créé par Harold le Hardÿ de Beaulieu - Roldy Management"

    @MainActor static func openWebsite() { NSWorkspace.shared.open(websiteURL) }
}

/// The Roldy Management logo (white on transparent, so it sits on a dark card), the credit line and the website link.
struct RoldyCreditCard: View {
    var markWidth: CGFloat = 96

    var body: some View {
        HStack(spacing: IslandSpacing.m) {
            RoldyMark(width: markWidth, opacity: 1)
            VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                Text(RoldyBrand.creditLine)
                    .font(.islandBody).foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                Button(RoldyBrand.websiteHost, systemImage: "arrow.up.right.square") { RoldyBrand.openWebsite() }
                    .buttonStyle(IslandButtonStyle())
                    .help("Ouvre \(RoldyBrand.websiteHost) dans le navigateur.")
            }
            Spacer(minLength: 0)
        }
        .padding(IslandSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(IslandSurface.notchBlack))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
    }
}
