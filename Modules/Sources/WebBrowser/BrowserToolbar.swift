import ComposableArchitecture
import SwiftUI

/// Bookmark picker, navigation buttons, address field and the actions menu. Rendering only.
struct BrowserToolbar: View {
    let store: StoreOf<BrowserFeature>

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                bookmarkMenu
                Spacer(minLength: 0)
                moreMenu
            }
            HStack(spacing: 4) {
                iconButton("chevron.backward", "Browser Back", enabled: store.navigation.canGoBack) {
                    store.send(.goBackTapped)
                }
                iconButton("chevron.forward", "Browser Forward", enabled: store.navigation.canGoForward) {
                    store.send(.goForwardTapped)
                }
                addressField
                iconButton(
                    store.navigation.isLoading ? "xmark" : "arrow.clockwise",
                    store.navigation.isLoading ? "Browser Stop" : "Browser Reload",
                    enabled: store.selectedID != nil
                ) {
                    store.send(.reloadOrStopTapped)
                }
            }
        }
    }

    private var bookmarkMenu: some View {
        Menu {
            Picker(BrowserStrings.text("Browser Bookmarks"), selection: Binding(
                get: { store.selectedID },
                set: { if let id = $0 { store.send(.selectBookmark(id)) } }
            )) {
                ForEach(store.bookmarks) { bookmark in
                    Text(bookmark.displayTitle).tag(Optional(bookmark.id))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label(store.selectedBookmark?.displayTitle ?? BrowserStrings.text("Browser"), systemImage: "bookmark")
                .lineLimit(1)
                .font(.callout.weight(.semibold))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize(horizontal: false, vertical: true)
        .help(BrowserStrings.text("Browser Bookmarks"))
        .accessibilityLabel(BrowserStrings.text("Browser Bookmarks"))
        .accessibilityValue(store.selectedBookmark?.displayTitle ?? "")
    }

    private var moreMenu: some View {
        Menu {
            Button(BrowserStrings.text("Browser Home"), systemImage: "house") { store.send(.homeTapped) }
            if let id = store.selectedID {
                Toggle(BrowserStrings.text("Browser Mobile Version"), isOn: Binding(
                    get: { store.selectedBookmark?.usesMobileUserAgent ?? false },
                    set: { _ in store.send(.mobileUserAgentToggled(id)) }
                ))
            }
            Button(BrowserStrings.text("Browser Add Current Page"), systemImage: "bookmark.badge.plus") {
                store.send(.addCurrentPageTapped)
            }
            Divider()
            Button(BrowserStrings.text("Browser Open In Default Browser"), systemImage: "safari") {
                store.send(.openInDefaultBrowserTapped)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(BrowserStrings.text("Browser More"))
        .accessibilityLabel(BrowserStrings.text("Browser More"))
    }

    private var addressField: some View {
        TextField(BrowserStrings.text("Browser Address"), text: Binding(
            get: { store.addressText },
            set: { store.send(.addressTextChanged($0)) }
        ))
        .textFieldStyle(.roundedBorder)
        .autocorrectionDisabled()
        .onSubmit { store.send(.addressSubmitted) }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.red, lineWidth: 1)
                .opacity(store.showsInvalidAddress ? 1 : 0)
                .allowsHitTesting(false)
        }
        .help(BrowserStrings.text(store.showsInvalidAddress ? "Browser Invalid Address" : "Browser Address"))
        .accessibilityLabel(BrowserStrings.text("Browser Address"))
        .accessibilityHint(store.showsInvalidAddress ? BrowserStrings.text("Browser Invalid Address") : "")
    }

    private func iconButton(_ symbol: String, _ key: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .help(BrowserStrings.text(key))
        .accessibilityLabel(BrowserStrings.text(key))
    }
}
