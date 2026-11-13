import ComposableArchitecture
import SwiftUI

/// Content of the Browser tab in the menu-bar list and Only Control.
public struct BrowserPanelView: View {
    let store: StoreOf<BrowserFeature>
    @ObservedObject var pool: BrowserWebViewPool
    let compact: Bool
    let onManageBookmarks: () -> Void

    public init(
        store: StoreOf<BrowserFeature>,
        pool: BrowserWebViewPool = .shared,
        compact: Bool,
        onManageBookmarks: @escaping () -> Void
    ) {
        self.store = store
        self.pool = pool
        self.compact = compact
        self.onManageBookmarks = onManageBookmarks
    }

    public var body: some View {
        VStack(spacing: 8) {
            if store.bookmarks.isEmpty {
                BrowserEmptyView(onManageBookmarks: onManageBookmarks)
            } else {
                BrowserToolbar(store: store)
                    .padding(8)
                    .modifier(BrowserToolbarBackground())
                page
            }
        }
        .padding(.horizontal, compact ? 12 : 30)
        .padding(.vertical, compact ? 6 : 12)
        .onAppear { store.send(.onAppear) }
    }

    private var page: some View {
        ZStack(alignment: .top) {
            if let id = store.selectedID {
                BrowserWebViewHost(pool: pool, bookmarkID: id)
            }
            if let failure = store.navigation.failureDescription {
                ContentUnavailableView(
                    BrowserStrings.text("Browser Load Failed"),
                    systemImage: "wifi.exclamationmark",
                    description: Text(failure)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
            }
            if store.navigation.isLoading {
                ProgressView(value: store.navigation.progress)
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.primary.opacity(0.08))
        }
    }
}

private struct BrowserToolbarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
