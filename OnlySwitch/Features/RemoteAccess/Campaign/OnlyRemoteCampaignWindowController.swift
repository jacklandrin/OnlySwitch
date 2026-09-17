import AppKit
import ComposableArchitecture
import Extensions
import SwiftUI

@MainActor
final class OnlyRemoteCampaignWindowController: NSWindowController, NSWindowDelegate {
    private let store: StoreOf<OnlyRemoteCampaignFeature>
    private var didEvaluateCampaign = false

    init(
        store: StoreOf<OnlyRemoteCampaignFeature> = Store(
            initialState: OnlyRemoteCampaignFeature.State()
        ) {
            OnlyRemoteCampaignFeature()
        }
    ) {
        self.store = store

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "OnlyRemote for iPhone and iPad".localized()
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: OnlyRemoteCampaignView(
                store: store,
                closeWindow: { [weak self] in
                    self?.close()
                }
            )
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func presentIfNeeded() {
        guard !didEvaluateCampaign else { return }
        didEvaluateCampaign = true

#if DEBUG
        store.send(.launch(forcePresentation: true))
#else
        store.send(.launch(forcePresentation: false))
#endif
        guard store.isPresented, let window else { return }

        window.title = "OnlyRemote for iPhone and iPad".localized()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if store.isPresented {
            store.send(.dismissTapped)
        }
    }
}
