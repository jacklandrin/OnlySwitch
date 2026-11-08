import Foundation
import RemoteCore
import UIKit

extension RemoteReviewDemoRuntime {
    nonisolated static func makeBrightnessSnapshot() -> RemoteBrightnessSnapshot {
        .init(revision: 1, displays: [
            .init(id: 1, name: "Built-in Retina Display", control: .native, level: 0.7, hasError: false),
            .init(id: 2, name: "Studio Display", control: .ddc, level: 0.5, hasError: false),
        ])
    }

    /// Sample screenshots: a title, an SF Symbol and a gradient, drawn on demand (no bundled assets).
    private struct DemoScreenshot: Sendable {
        let id: UUID
        let title: String
        let symbolName: String
        /// Gradient start and end as 0xRRGGBB.
        let colors: (UInt32, UInt32)
        let isPinned: Bool
        let minutesAgo: Double
    }

    private nonisolated static let demoScreenshots: [DemoScreenshot] = [
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000D101")!, title: "Release Notes", symbolName: "doc.text.fill",
              colors: (0x4B3FD8, 0x9B4DDB), isPinned: true, minutesAgo: 240),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000D102")!, title: "Dashboard", symbolName: "chart.bar.xaxis",
              colors: (0x1FA5B8, 0x2D6BE4), isPinned: false, minutesAgo: 5),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000D103")!, title: "Design Review", symbolName: "paintpalette.fill",
              colors: (0xF2994A, 0xE0457B), isPinned: false, minutesAgo: 45),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000D104")!, title: "Terminal", symbolName: "terminal.fill",
              colors: (0x3A3F47, 0x111316), isPinned: false, minutesAgo: 180),
    ]

    /// Four PNG screenshots in the Mac's display order (pinned first, then newest first).
    nonisolated static func makeScreenshotLibrary() -> RemoteScreenshotLibrary {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let items = demoScreenshots.map { shot in
            RemoteScreenshotItem(
                id: shot.id,
                fileName: "\(shot.title).png",
                contentType: "public.png",
                createdAt: now.addingTimeInterval(-shot.minutesAgo * 60),
                isPinned: shot.isPinned,
                revision: 1,
                byteCount: 180_000
            )
        }
        return .init(revision: 1, isCollectionEnabled: true, items: items)
    }

    private nonisolated static func cgColor(_ rgb: UInt32) -> CGColor {
        CGColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    /// Renders a 16:10 sample screenshot `width` points wide at scale 1, so pixels equal points.
    nonisolated static func demoScreenshotImage(for item: RemoteScreenshotItem, width: CGFloat) -> UIImage {
        let shot = demoScreenshots.first { $0.id == item.id }
        let size = CGSize(width: width, height: (width * 10 / 16).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = shot?.colors ?? (0x8E8E93, 0x48484A)
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [cgColor(colors.0), cgColor(colors.1)] as CFArray,
                locations: [0, 1]
            )
            if let gradient {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }
            let unit = size.height / 10
            let configuration = UIImage.SymbolConfiguration(pointSize: unit * 2.6, weight: .semibold)
            if let symbol = UIImage(systemName: shot?.symbolName ?? "photo", withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                symbol.draw(at: CGPoint(x: (size.width - symbol.size.width) / 2, y: unit * 2.4))
            }
            let title = (shot?.title ?? item.fileName) as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: unit * 0.9, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let titleSize = title.size(withAttributes: attributes)
            title.draw(at: CGPoint(x: (size.width - titleSize.width) / 2, y: unit * 6.4), withAttributes: attributes)
        }
    }

    nonisolated static func makeSoundMixerSnapshot() -> RemoteSoundMixerSnapshot {
        .init(
            revision: 1,
            isEnabled: true,
            systemVolume: 62,
            output: .init(name: "Studio Display Speakers", symbolName: "display"),
            apps: [
                .init(
                    id: "com.apple.Music",
                    name: "Music",
                    volume: 80,
                    isMuted: false,
                    equalizer: .init(gains: [3, 2, 1, 0, -1, 0, 1, 2, 3, 2], status: .active),
                    routing: .init(selectedDeviceIDs: [], status: .followingSystem)
                ),
                .init(
                    id: "com.apple.Safari",
                    name: "Safari",
                    volume: 45,
                    isMuted: false,
                    equalizer: .init(gains: [], status: .flat),
                    routing: .init(selectedDeviceIDs: [], status: .followingSystem)
                ),
            ],
            outputDevices: [
                .init(id: "review-studio-display", name: "Studio Display Speakers", isDefault: true),
                .init(id: "review-airpods", name: "AirPods Pro", isDefault: false),
            ]
        )
    }

    nonisolated static func makeDescriptor(
        id: RemoteControlID,
        title: String,
        behavior: RemoteControlDescriptor.Behavior,
        icon: String,
        supportsStatus: Bool
    ) -> RemoteControlDescriptor {
        .init(
            id: id,
            title: title,
            behavior: behavior,
            icon: .systemSymbol(icon),
            isAvailable: true,
            unavailableReason: nil,
            isDestructive: false,
            supportsStatus: supportsStatus,
            supportsSecondaryInformation: supportsStatus
        )
    }

    nonisolated static func makeStatus(
        id: RemoteControlID,
        isOn: Bool,
        revision: UInt64,
        updatedAt: Date
    ) -> RemoteControlStatus {
        .init(
            id: id,
            isAvailable: true,
            unavailableReason: nil,
            isOn: isOn,
            secondaryInformation: isOn ? "On" : "Off",
            isProcessing: false,
            revision: revision,
            updatedAt: updatedAt
        )
    }
}
