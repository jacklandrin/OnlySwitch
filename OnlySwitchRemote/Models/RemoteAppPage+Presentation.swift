import SwiftUI

extension RemoteAppPage {
    var title: LocalizedStringKey {
        switch self {
        case .controls: "Controls"
        case .systemMonitor: "System Monitor"
        case .soundMixer: "Sound Mixer"
        case .brightness: "Brightness"
        case .codexUsage: "Codex Usage"
        case .claudeUsage: "Claude Usage"
        case .aphrodite: "Aphrodite"
        }
    }

    var tabSymbol: String? {
        switch self {
        case .controls: "switch.2"
        case .systemMonitor: "waveform.path.ecg"
        case .soundMixer: "slider.horizontal.3"
        case .brightness: "sun.max"
        case .aphrodite: "sparkles.rectangle.stack"
        case .codexUsage, .claudeUsage: nil
        }
    }

    /// Template brand logo from the asset catalog, used when the page has no SF Symbol.
    var tabImageName: String? {
        switch self {
        case .codexUsage: RemoteCodexUsagePresentation.tabImageName
        case .claudeUsage: RemoteClaudeUsagePresentation.tabImageName
        case .controls, .systemMonitor, .soundMixer, .brightness, .aphrodite: nil
        }
    }

    var requiresPlus: Bool {
        switch self {
        case .soundMixer, .brightness, .aphrodite: true
        case .controls, .systemMonitor, .codexUsage, .claudeUsage: false
        }
    }

    var isAlwaysVisible: Bool { self == .controls }
}
