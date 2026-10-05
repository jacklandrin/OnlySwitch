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
                },
                showQRCode: {
                    QRCodeWindowController.shared.show(
                        url: URL(string: "https://raw.githubusercontent.com/jacklandrin/OnlySwitch/main/OnlySwitch/Resource/Ads/OnlyRemoteQRCode.jpeg")!
                    )
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

@MainActor
final class QRCodeWindowController: NSWindowController {
    static let shared = QRCodeWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(url: URL) {
        guard let window else { return }
        window.contentViewController = NSHostingController(
            rootView: QRCodeView(url: url, close: { [weak self] in self?.close() })
        )
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct QRCodeView: View {
    let url: URL
    let close: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().interpolation(.none).scaledToFit()
                } else if phase.error != nil {
                    Image(systemName: "qrcode").font(.system(size: 180)).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .padding(24)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .padding(8)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(14)
            .accessibilityLabel("Close".localized())
        }
        .frame(width: 440, height: 500)
        .appKitWindowDrag()
    }
}
