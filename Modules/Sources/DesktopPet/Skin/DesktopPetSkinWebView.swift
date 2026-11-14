import AppKit
import DesktopPetSkinKit
import OSLog
import SwiftUI
import WebKit

private let logger = Logger(subsystem: "com.jacklandrin.OnlySwitch", category: "DesktopPetSkin")

enum DesktopPetSkinNavigationPolicy {
    static func allows(url: URL?, isInitialLoad: Bool) -> Bool {
        isInitialLoad && (url == nil || url?.absoluteString == "about:blank")
    }
}

/// Never takes mouse events, so SwiftUI keeps owning click, drag and the context menu.
final class DesktopPetSkinWKWebView: WKWebView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }
}

/// Renders an untrusted skin with content JavaScript disabled, no persistent storage, no
/// navigation and a strict CSP. Native code changes only the contract's `<html>` attributes.
public struct DesktopPetSkinWebView: NSViewRepresentable {
    let skin: DesktopPetSkin
    let state: DesktopPetAnimationState
    let reduceMotion: Bool
    let isPaused: Bool

    public init(skin: DesktopPetSkin, state: DesktopPetAnimationState, reduceMotion: Bool, isPaused: Bool) {
        self.skin = skin
        self.state = state
        self.reduceMotion = reduceMotion
        self.isPaused = isPaused
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.suppressesIncrementalRendering = true
        let view = DesktopPetSkinWKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.underPageBackgroundColor = .clear
        view.allowsLinkPreview = false
        view.allowsMagnification = false
        view.navigationDelegate = context.coordinator
        view.setAccessibilityElement(false)
        load(into: view, coordinator: context.coordinator)
        return view
    }

    public func updateNSView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.skinID != skin.id || coordinator.markup != skin.markup {
            load(into: view, coordinator: coordinator)
            return
        }
        let script = DesktopPetSkinAttributes.script(attributes)
        guard script != coordinator.lastScript else { return }
        coordinator.lastScript = script
        view.evaluateJavaScript(script, in: nil, in: .defaultClient) { result in
            if case .failure = result { logger.warning("Skin attribute update failed") }
        }
    }

    public static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.navigationDelegate = nil
    }

    private var attributes: [DesktopPetSkinAttributes.Attribute] {
        DesktopPetSkinAttributes.values(for: state, reduceMotion: reduceMotion, isPaused: isPaused)
    }

    private func load(into view: WKWebView, coordinator: Coordinator) {
        coordinator.skinID = skin.id
        coordinator.markup = skin.markup
        coordinator.lastScript = DesktopPetSkinAttributes.script(attributes)
        coordinator.isInitialLoad = true
        view.loadHTMLString(
            DesktopPetSkinDocument.make(markup: skin.markup, attributes: attributes),
            baseURL: nil
        )
    }

    @MainActor
    public final class Coordinator: NSObject, WKNavigationDelegate {
        var skinID: UUID?
        var markup: String?
        var lastScript: String?
        var isInitialLoad = true

        public func webView(
            _ webView: WKWebView,
            decidePolicyFor action: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            let allowed = DesktopPetSkinNavigationPolicy.allows(url: action.request.url, isInitialLoad: isInitialLoad)
            isInitialLoad = false
            return allowed ? .allow : .cancel
        }

        public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            logger.error("Skin web content process terminated")
        }
    }
}
