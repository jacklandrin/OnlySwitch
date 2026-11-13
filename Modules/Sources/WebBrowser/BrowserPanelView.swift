import ComposableArchitecture
import SwiftUI

/// Content of the Browser tab in the menu-bar list and Only Control. The page fills the tab; the toolbar
/// floats over its top edge and appears only when the pointer rests there (see `BrowserToolbarReveal`).
public struct BrowserPanelView: View {
    let store: StoreOf<BrowserFeature>
    @ObservedObject var pool: BrowserWebViewPool
    let compact: Bool
    let onManageBookmarks: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @FocusState private var addressFocused: Bool
    @State private var pointerWantsToolbar = false
    @State private var hoveringToolbar = false
    @State private var toolbarRevealed = false
    @State private var toolbarHeight: CGFloat = 0
    @State private var revealTask: Task<Void, Never>?

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
        Group {
            if store.bookmarks.isEmpty {
                BrowserEmptyView(onManageBookmarks: onManageBookmarks)
            } else {
                page
            }
        }
        .padding(.horizontal, compact ? 12 : 30)
        .padding(.vertical, compact ? 6 : 12)
        .onAppear { store.send(.onAppear) }
        .onDisappear {
            revealTask?.cancel()
            pointerWantsToolbar = false
            hoveringToolbar = false
            toolbarRevealed = false
        }
    }

    private var showsToolbar: Bool {
        toolbarRevealed || BrowserToolbarReveal.isPinned(
            addressFocused: addressFocused,
            showsInvalidAddress: store.showsInvalidAddress,
            voiceOverEnabled: voiceOverEnabled
        )
    }

    private var page: some View {
        ZStack(alignment: .top) {
            if let id = store.selectedID {
                BrowserWebViewHost(
                    pool: pool,
                    bookmarkID: id,
                    toolbarIsVisible: showsToolbar,
                    toolbarHeight: toolbarHeight
                ) { wants in
                    pointerWantsToolbar = wants
                    scheduleReveal()
                }
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
            revealHandle
                .opacity(showsToolbar ? 0 : 1)
            // Kept in the hierarchy while hidden so an open bookmark menu or the address field's focus
            // survives the toolbar sliding away.
            toolbar
            focusAddressShortcut
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.primary.opacity(0.08))
        }
    }

    private var toolbar: some View {
        BrowserToolbar(store: store, addressFocused: $addressFocused)
            .padding(8)
            .modifier(BrowserToolbarBackground())
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .padding(6)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { toolbarHeight = $0 }
            .onHover { hovering in
                hoveringToolbar = hovering
                scheduleReveal()
            }
            .offset(y: showsToolbar || reduceMotion ? 0 : -(toolbarHeight + 6))
            .opacity(showsToolbar ? 1 : 0)
            .allowsHitTesting(showsToolbar)
            .accessibilityHidden(!showsToolbar)
    }

    /// A faint grabber hinting that the toolbar is tucked away at the top.
    private var revealHandle: some View {
        Capsule()
            .fill(.secondary.opacity(0.35))
            .frame(width: 36, height: 4)
            .padding(.top, 5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// ⌘L reveals the toolbar and focuses the address field, as in Safari.
    private var focusAddressShortcut: some View {
        Button(BrowserStrings.text("Browser Address")) {
            setToolbarRevealed(true)
            addressFocused = true
        }
        .keyboardShortcut("l", modifiers: .command)
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func scheduleReveal() {
        revealTask?.cancel()
        let target = pointerWantsToolbar || hoveringToolbar
        guard target != toolbarRevealed else { return }
        revealTask = Task { @MainActor in
            try? await Task.sleep(for: BrowserToolbarReveal.delay(revealing: target))
            guard !Task.isCancelled else { return }
            setToolbarRevealed(target)
        }
    }

    private func setToolbarRevealed(_ revealed: Bool) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) {
            toolbarRevealed = revealed
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
