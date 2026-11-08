import ComposableArchitecture
import RemoteCore
import SwiftUI

/// The Screenshots & Record tab: the selected Mac's screenshots and recordings as an adaptive grid.
/// Renders reducer state and sends actions only.
struct RemoteScreenshotsView: View {
    let store: StoreOf<RemoteScreenshotsFeature>
    @ScaledMetric(relativeTo: .body) private var minimumCellWidth: CGFloat = 150
    /// iPad and other regular widths get larger cells so screenshots stay legible.
    @ScaledMetric(relativeTo: .body) private var regularMinimumCellWidth: CGFloat = 240
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if store.selectedMacID == nil {
                ContentUnavailableView(
                    "No Mac Selected",
                    systemImage: "desktopcomputer",
                    description: Text("Select a paired Mac from the navigation bar.")
                )
            } else if let message = store.availabilityMessage {
                ContentUnavailableView(
                    "Screenshots & Record",
                    systemImage: "exclamationmark.triangle",
                    description: Text(verbatim: message)
                )
            } else if let library = store.library {
                if store.items.isEmpty {
                    emptyState(isCollectionEnabled: library.isCollectionEnabled)
                } else {
                    grid(isCollectionEnabled: library.isCollectionEnabled)
                }
            } else if store.isOffline {
                ContentUnavailableView(
                    "Screenshots & Record",
                    systemImage: "wifi.slash",
                    description: Text("The selected Mac is offline.")
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Screenshots & Record")
        // The viewer sheet is presented from the app root; see `RemoteScreenshotDetailPresentation`.
        .modifier(RemoteScreenshotPromptsModifier(store: store, isActive: store.selectedItemID == nil))
    }

    private func emptyState(isCollectionEnabled: Bool) -> some View {
        VStack(spacing: 0) {
            if store.isOffline {
                RemoteScreenshotsBanner(
                    message: "Offline — showing screenshots saved on this device.",
                    systemImage: "wifi.slash"
                )
                .padding(16)
            }
            ContentUnavailableView {
                Label("No Screenshots", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text(isCollectionEnabled
                     ? "Screenshots and screen recordings you take on this Mac appear here."
                     : "Turn on screenshot collection in OnlySwitch on the Mac to see new screenshots and recordings here.")
            }
        }
        .padding(.bottom, RemotePageTabBar.contentBottomInset)
    }

    private func grid(isCollectionEnabled: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if store.isOffline {
                    RemoteScreenshotsBanner(
                        message: "Offline — showing screenshots saved on this device.",
                        systemImage: "wifi.slash"
                    )
                } else if isCollectionEnabled == false {
                    RemoteScreenshotsBanner(
                        message: "Screenshot collection is off on the Mac. New screenshots won't appear here.",
                        systemImage: "camera.badge.ellipsis"
                    )
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(store.items) { item in
                        RemoteScreenshotCell(store: store, item: item)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, RemotePageTabBar.contentBottomInset + 16)
            .frame(maxWidth: 1_100)
            .frame(maxWidth: .infinity)
        }
    }

    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [GridItem(.adaptive(minimum: min(regularMinimumCellWidth, 420), maximum: 480), spacing: 16)]
        }
        return [GridItem(.adaptive(minimum: min(minimumCellWidth, 320), maximum: 360), spacing: 12)]
    }
}
