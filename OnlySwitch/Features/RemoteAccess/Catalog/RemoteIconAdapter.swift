import AppKit
import RemoteCore
import Switches

@MainActor
enum RemoteIconAdapter {
    static func icon(for type: SwitchType, barInfo: SwitchBarInfo) -> RemoteControlDescriptor.Icon {
        if let symbolName = symbolName(for: type) {
            return .systemSymbol(symbolName)
        }

        guard let image = barInfo.offImage ?? barInfo.onImage,
              let data = pngData(from: image) else {
            return .systemSymbol("switch.2")
        }
        return .png(data)
    }

    static func icon(for evolution: EvolutionItem) -> RemoteControlDescriptor.Icon {
        .systemSymbol(
            evolution.iconName ?? (evolution.controlType == .Button
                ? "button.programmable.square.fill"
                : "lightswitch.on.square")
        )
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 60,
            pixelsHigh: 60,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        representation.size = NSSize(width: 60, height: 60)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        image.draw(
            in: NSRect(x: 0, y: 0, width: 60, height: 60),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        return representation.representation(using: .png, properties: [:])
    }

    private static func symbolName(for type: SwitchType) -> String? {
        switch type {
        case .hiddeDesktop, .darkMode, .bluetooth, .showExtensionName, .dockRecent,
             .spotify, .applemusic, .hideMenubarIcons, .trueTone, .topSticker, .aiCommender:
            nil
        case .topNotch: "laptopwithnotch"
        case .mute: "speaker.wave.2.circle"
        case .keepAwake: "lock.slash"
        case .screenSaver: "display"
        case .nightShift: "moon.stars"
        case .autohideDock: "dock.rectangle"
        case .autohideMenuBar: "menubar.rectangle"
        case .airPods: "airpodspro"
        case .xcodeCache: "hammer.circle"
        case .hiddenFiles: "eye.slash"
        case .radioStation: "radio"
        case .emptyTrash: "trash"
        case .emptyPasteboard: "doc.on.clipboard"
        case .showUserLibrary: "building.columns"
        case .pomodoroTimer: "timer"
        case .smallLaunchpadIcon: "square.grid.4x3.fill"
        case .lowpowerMode: "bolt.circle.fill"
        case .muteMicrophone: "mic.circle"
        case .showFinderPathbar: "greaterthan.square"
        case .screenTest: "display.trianglebadge.exclamationmark"
        case .fkey: "sun.max"
        case .backNoises: "ear"
        case .dimScreen: "sun.max.fill"
        case .ejectDiscs: "eject.circle"
        case .hideWindows: "macwindow"
        case .keyLight: "light.min"
        case .authenticator: "key"
        }
    }
}
