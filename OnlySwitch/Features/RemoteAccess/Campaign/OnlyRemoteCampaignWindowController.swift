import AppKit
import Combine
import ComposableArchitecture
import Extensions
import SwiftUI
import Utilities

private let campaignWindowContentSize = NSSize(width: 520, height: 560)
private let qrCodeWindowContentSize = NSSize(width: 400, height: 440)

@MainActor
final class OnlyRemoteCampaignWindowController: NSWindowController, NSWindowDelegate {
    private let store: StoreOf<OnlyRemoteCampaignFeature>
    private var documentObservation: AnyCancellable?
    private var renderer: OnlyRemoteCampaignView?
    private var renderingDate: String?

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
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OnlySwitch · OnlyRemote"
        window.minSize = NSSize(width: 480, height: 500)
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        documentObservation = store.publisher.document.removeDuplicates().sink { [weak self] document in
            self?.render(document)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(updateLanguage), name: .changeSettings, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func presentIfNeeded() {
        store.send(.launch)
    }

    private func render(_ document: OnlyRemoteCampaignDocument?) {
        guard let document else {
            renderingDate = nil
            renderer?.stopLoading()
            renderer = nil
            window?.contentView = nil
            close()
            return
        }
        guard renderingDate != document.manifest.date else { return }
        let date = document.manifest.date
        renderingDate = date
        let view = OnlyRemoteCampaignView(
            language: LanguageManager.sharedManager.currentLang,
            onLoaded: { [weak self] in self?.presentLoadedDocument(date: date) },
            onFailed: { [weak self] in
                guard let self, self.renderingDate == date else { return }
                self.store.send(.pageFailed(date))
            },
            onDownload: { [weak self] in self?.store.send(.showQRCodeTapped) }
        )
        renderer = view
        window?.contentView = view
        view.loadHTMLString(document.html, baseURL: nil)
    }

    private func presentLoadedDocument(date: String) {
        guard renderingDate == date, store.document?.manifest.date == date,
              !store.isPresented, let window else { return }
        updateLanguage()
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let available = screen?.visibleFrame.size ?? campaignWindowContentSize
        let size = NSSize(
            width: min(campaignWindowContentSize.width, available.width),
            height: min(campaignWindowContentSize.height, available.height)
        )
        window.setContentSize(size)
        centerOnCurrentScreen(window)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        // Only acknowledge a page after WebKit finished and the window was made visible.
        store.send(.pageLoaded(date))
    }

    @objc private func updateLanguage() {
        renderer?.updateLanguage(LanguageManager.sharedManager.currentLang)
    }

    func windowWillClose(_ notification: Notification) {
        if store.document != nil {
            store.send(.dismissTapped)
        }
    }
}

@MainActor
final class QRCodeWindowController: NSWindowController {
    static let shared = QRCodeWindowController()
    static let onlyRemoteQRCodeURL = URL(
        string: "https://raw.githubusercontent.com/jacklandrin/OnlySwitch/main/OnlySwitch/Resource/Ads/OnlyRemoteQRCode.jpeg"
    )!

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
