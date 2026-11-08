import SwiftUI

/// An informational strip above the grid (offline cache, collection turned off).
struct RemoteScreenshotsBanner: View {
    let message: LocalizedStringKey
    let systemImage: String

    var body: some View {
        RemoteSystemMonitorCardSurface {
            Label(message, systemImage: systemImage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
