import AppKit
import ComposableArchitecture
import Extensions
import SwiftUI

private let campaignWindowContentSize = NSSize(width: 460, height: 440)
private let qrCodeWindowContentSize = NSSize(width: 400, height: 440)

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
            contentRect: NSRect(origin: .zero, size: campaignWindowContentSize),
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
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        centerWhenPresented(window, contentSize: campaignWindowContentSize)
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
        let window = QRCodeWindow(
            contentRect: NSRect(origin: .zero, size: qrCodeWindowContentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
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
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        centerWhenPresented(window, contentSize: qrCodeWindowContentSize)
    }
}

private final class QRCodeWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
private func centerOnCurrentScreen(_ window: NSWindow) {
    let mouseLocation = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
    guard let screen else { return }

    let frame = window.frame
    window.setFrameOrigin(
        NSPoint(
            x: screen.frame.midX - frame.width / 2,
            y: screen.frame.midY - frame.height / 2
        )
    )
}

@MainActor
private func centerWhenPresented(_ window: NSWindow, contentSize: NSSize) {
    window.setContentSize(contentSize)
    centerOnCurrentScreen(window)
    Task { @MainActor [weak window] in
        guard let window else { return }
        window.setContentSize(contentSize)
        centerOnCurrentScreen(window)
    }
}

private struct QRCodeView: View {
    let url: URL
    let close: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().interpolation(.none).scaledToFit()
                } else if phase.error != nil {
                    Image(systemName: "qrcode").font(.system(size: 140)).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .frame(width: 260, height: 260)

            VStack(spacing: 6) {
                Text("Download OnlyRemote on the App Store".localized())
                    .font(.headline)
                Text("Control OnlySwitch from your iPhone or iPad".localized())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .padding(8)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(16)
            .accessibilityLabel("Close".localized())
        }
        .frame(width: 400, height: 440)
        .appKitWindowDrag()
    }
}
