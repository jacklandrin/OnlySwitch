import ApplicationServices
import AppKit
import CoreGraphics
import Dependencies
import ScreenCaptureKit

struct DockPreviewClient: Sendable {
    var authorizationStatus: @MainActor @Sendable () -> DockPreviewAuthorization
    var requestAuthorization: @MainActor @Sendable () -> DockPreviewAuthorization
    var hoverEvents: @MainActor @Sendable () -> AsyncStream<DockHoverEvent?>
    var windows: @MainActor @Sendable (pid_t) async throws -> [DockPreviewWindow]
    var capture: @MainActor @Sendable (DockPreviewWindow) async throws -> Data
    var activate: @MainActor @Sendable (DockPreviewWindow) async throws -> Void
    var updatePreviewFrame: @MainActor @Sendable (CGRect?) -> Void
    var isMediaPlaying: @MainActor @Sendable (DockPreviewMediaPlayer) -> Bool
    var sendMediaCommand: @MainActor @Sendable (DockPreviewMediaPlayer, DockPreviewMediaCommand) -> Void
    var persistEnabled: @MainActor @Sendable (Bool) -> Void
    var stop: @MainActor @Sendable () async -> Void
}

extension DockPreviewClient: DependencyKey, TestDependencyKey {
    static let testValue = Self(
        authorizationStatus: { .unknown },
        requestAuthorization: { .unknown },
        hoverEvents: { AsyncStream { $0.finish() } },
        windows: { _ in [] },
        capture: { _ in Data() },
        activate: { _ in },
        updatePreviewFrame: { _ in },
        isMediaPlaying: { _ in false },
        sendMediaCommand: { _, _ in },
        persistEnabled: { _ in },
        stop: {}
    )

    static let liveValue = Self(
        authorizationStatus: { DockPreviewRuntime.shared.authorizationStatus() },
        requestAuthorization: { DockPreviewRuntime.shared.requestAuthorization() },
        hoverEvents: { DockPreviewRuntime.shared.hoverEvents() },
        windows: { try await DockPreviewRuntime.shared.windows(pid: $0) },
        capture: { try await DockPreviewRuntime.shared.capture($0) },
        activate: { try await DockPreviewRuntime.shared.activate($0) },
        updatePreviewFrame: { DockPreviewRuntime.shared.updatePreviewFrame($0) },
        isMediaPlaying: { DockPreviewMediaRuntime.isPlaying($0) },
        sendMediaCommand: { DockPreviewMediaRuntime.send($1, to: $0) },
        persistEnabled: { Preferences.shared.dockPreviewEnabled = $0 },
        stop: { await DockPreviewRuntime.shared.stop() }
    )
}

extension DependencyValues {
    var dockPreview: DockPreviewClient {
        get { self[DockPreviewClient.self] }
        set { self[DockPreviewClient.self] = newValue }
    }
}

@MainActor
private final class DockPreviewRuntime {
    static let shared = DockPreviewRuntime()

    private var observationTask: Task<Void, Never>?
    private var activationTargets: [CGWindowID: AXUIElement] = [:]
    private var lastHover: DockHoverEvent?
    private var previewFrame: CGRect?
    private var pendingExitSince: ContinuousClock.Instant?

    private init() {}

    func authorizationStatus() -> DockPreviewAuthorization {
        .init(
            accessibility: AXIsProcessTrusted(),
            screenRecording: CGPreflightScreenCaptureAccess()
        )
    }

    func requestAuthorization() -> DockPreviewAuthorization {
        let accessibility = AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        )
        let screenRecording = CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
        return .init(accessibility: accessibility, screenRecording: screenRecording)
    }

    func hoverEvents() -> AsyncStream<DockHoverEvent?> {
        observationTask?.cancel()
        lastHover = nil

        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { @MainActor [weak self] in
                defer { continuation.finish() }
                var stabilizer = DockHoverStabilizer()
                while !Task.isCancelled {
                    let directHit = self?.dockHover(at: CGEvent(source: nil)?.location)
                    let event = self?.resolvedHover(dockHover: directHit)
                    self?.lastHover = event
                    if case let .changed(event) = stabilizer.update(
                        event,
                        isDirectHit: directHit != nil
                    ) {
                        continuation.yield(event)
                    }
                    do {
                        try await Task.sleep(for: .milliseconds(80))
                    } catch {
                        return
                    }
                }
            }
            observationTask = task
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func windows(pid: pid_t) async throws -> [DockPreviewWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: true
        )
        let candidates = content.windows.filter { window in
            window.owningApplication?.processID == pid &&
                window.windowLayer == 0 &&
                window.frame.width > 1 &&
                window.frame.height > 1 &&
                !(window.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        .prefix(12)

        let axWindows = accessibilityWindows(pid: pid)
        // A slow result for a previous Dock item must not invalidate the
        // activation handles of the preview currently shown to the user.
        if activationTargets.count > 128 {
            activationTargets.removeAll(keepingCapacity: true)
        }

        return candidates.map { window in
            let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let matches = axWindows.filter {
                $0.title == title && framesMatch($0.frame, window.frame)
            }
            if matches.count == 1 {
                activationTargets[window.windowID] = matches[0].element
            }
            return DockPreviewWindow(
                id: window.windowID,
                title: title,
                pid: pid,
                frame: window.frame,
                isActivatable: matches.count == 1
            )
        }
    }

    func capture(_ window: DockPreviewWindow) async throws -> Data {
        let content = try await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: true
        )
        guard let source = content.windows.first(where: {
            $0.windowID == window.id && $0.owningApplication?.processID == window.pid
        }) else {
            throw DockPreviewFailure.capture
        }

        let filter = SCContentFilter(desktopIndependentWindow: source)
        let configuration = SCStreamConfiguration()
        let scale = min(1, min(320 / max(source.frame.width, 1), 200 / max(source.frame.height, 1)))
        configuration.width = max(1, Int(source.frame.width * scale))
        configuration.height = max(1, Int(source.frame.height * scale))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = false
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw DockPreviewFailure.capture
        }
        return data
    }

    func activate(_ window: DockPreviewWindow) async throws {
        guard window.isActivatable,
              let target = activationTargets[window.id],
              let application = NSRunningApplication(processIdentifier: window.pid)
        else {
            throw DockPreviewFailure.activation
        }
        guard application.activate() else {
            throw DockPreviewFailure.activation
        }
        guard AXUIElementPerformAction(target, kAXRaiseAction as CFString) == .success else {
            throw DockPreviewFailure.activation
        }
    }

    func stop() async {
        observationTask?.cancel()
        observationTask = nil
        lastHover = nil
        previewFrame = nil
        pendingExitSince = nil
        activationTargets.removeAll(keepingCapacity: false)
    }

    func updatePreviewFrame(_ frame: CGRect?) {
        previewFrame = frame
        if frame == nil {
            pendingExitSince = nil
        }
    }

    private func resolvedHover(dockHover: DockHoverEvent?) -> DockHoverEvent? {
        if let hover = dockHover {
            pendingExitSince = nil
            return hover
        }
        guard let lastHover else { return nil }

        let pointer = NSEvent.mouseLocation
        if let previewFrame {
            let corridor = lastHover.itemFrame
                .union(previewFrame)
                .insetBy(dx: -12, dy: -12)
            if previewFrame.contains(pointer) || corridor.contains(pointer) {
                pendingExitSince = nil
                return lastHover
            }
        }

        let clock = ContinuousClock()
        guard let pendingExitSince else {
            self.pendingExitSince = clock.now
            return lastHover
        }
        return pendingExitSince.duration(to: clock.now) < .milliseconds(300) ? lastHover : nil
    }

    private func dockHover(at point: CGPoint?) -> DockHoverEvent? {
        guard let point,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }

        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
        var rawElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            dockElement,
            Float(point.x),
            Float(point.y),
            &rawElement
        ) == .success,
        let hitElement = rawElement,
        let element = dockItem(containing: hitElement),
        axString(element, kAXSubroleAttribute as CFString) == (kAXApplicationDockItemSubrole as String),
        let url = axURL(element, kAXURLAttribute as CFString)
        else { return nil }

        let normalizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        guard let application = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == normalizedURL
        }),
        let itemFrame = axRect(element)
        else { return nil }

        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(mouseLocation, $0.frame, false)
        }) else { return nil }

        return .init(
            pid: application.processIdentifier,
            appName: application.localizedName ?? url.deletingPathExtension().lastPathComponent,
            itemFrame: appKitRect(fromAccessibilityRect: itemFrame),
            screenFrame: screen.visibleFrame,
            mediaPlayer: DockPreviewMediaPlayer(bundleIdentifier: application.bundleIdentifier)
        )
    }

    private func accessibilityWindows(pid: pid_t) -> [AccessibilityWindow] {
        let application = AXUIElementCreateApplication(pid)
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &rawValue
        ) == .success,
        let elements = rawValue as? [AXUIElement]
        else { return [] }

        return elements.compactMap { element in
            guard let title = axString(element, kAXTitleAttribute as CFString),
                  let frame = axRect(element)
            else { return nil }
            return .init(element: element, title: title, frame: frame)
        }
    }

    private func dockItem(containing element: AXUIElement) -> AXUIElement? {
        var current = element
        for _ in 0..<6 {
            if axString(current, kAXRoleAttribute as CFString) == (kAXDockItemRole as String) {
                return current
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                current,
                kAXParentAttribute as CFString,
                &parent
            ) == .success,
            let parent,
            CFGetTypeID(parent) == AXUIElementGetTypeID()
            else { return nil }
            current = parent as! AXUIElement
        }
        return nil
    }

    private func axString(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private func axURL(_ element: AXUIElement, _ attribute: CFString) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? URL
    }

    private func axRect(_ element: AXUIElement) -> CGRect? {
        var rawPosition: CFTypeRef?
        var rawSize: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &rawPosition
        ) == .success,
        AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &rawSize
        ) == .success,
        let rawPosition,
        let rawSize,
        CFGetTypeID(rawPosition) == AXValueGetTypeID(),
        CFGetTypeID(rawSize) == AXValueGetTypeID()
        else { return nil }

        let positionValue = rawPosition as! AXValue
        let sizeValue = rawSize as! AXValue
        guard
        AXValueGetType(positionValue) == .cgPoint,
        AXValueGetType(sizeValue) == .cgSize
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let tolerance: CGFloat = 4
        return abs(lhs.minX - rhs.minX) <= tolerance &&
            abs(lhs.minY - rhs.minY) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance &&
            abs(lhs.height - rhs.height) <= tolerance
    }

    private func appKitRect(fromAccessibilityRect rect: CGRect) -> CGRect {
        guard let primaryHeight = NSScreen.screens.first?.frame.maxY else { return rect }
        return CGRect(
            x: rect.minX,
            y: primaryHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

@MainActor
private enum DockPreviewMediaRuntime {
    /// Hovering must never launch a player or ask for Automation permission;
    /// without permission, the switches' cached notification state is used.
    static func isPlaying(_ player: DockPreviewMediaPlayer) -> Bool {
        guard let application = runningApplication(player) else { return false }
        let target = NSAppleEventDescriptor(processIdentifier: application.processIdentifier)
        let canAutomate = AEDeterminePermissionToAutomateTarget(
            target.aeDesc, typeWildCard, typeWildCard, false
        ) == noErr
        switch player {
        case .appleMusic:
            guard let musicPlayer = AppleMusicSwitch.shared.player else { return false }
            return (canAutomate ? musicPlayer.playbackState : AppleMusicSwitch.shared.state).isActiveState
        case .spotify:
            guard let spotifyPlayer = SpotifySwitch.shared.player else { return false }
            return (canAutomate ? spotifyPlayer.playbackState : SpotifySwitch.shared.state).isActiveState
        }
    }

    /// Commands must never launch a player that quit while the preview was open.
    static func send(_ command: DockPreviewMediaCommand, to player: DockPreviewMediaPlayer) {
        guard runningApplication(player) != nil else { return }
        switch player {
        case .appleMusic:
            guard let music = AppleMusicSwitch.shared.player?.applemusicApp else { return }
            switch command {
            case .previousTrack: music.previousTrack?()
            case .playPause: music.playpause?()
            case .nextTrack: music.nextTrack?()
            }
        case .spotify:
            guard let spotify = SpotifySwitch.shared.player?.spotifyApp else { return }
            switch command {
            case .previousTrack: spotify.previousTrack?()
            case .playPause: spotify.playpause?()
            case .nextTrack: spotify.nextTrack?()
            }
        }
    }

    private static func runningApplication(_ player: DockPreviewMediaPlayer) -> NSRunningApplication? {
        let bundleIdentifier = switch player {
        case .appleMusic: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
    }
}

private struct AccessibilityWindow {
    var element: AXUIElement
    var title: String
    var frame: CGRect
}

