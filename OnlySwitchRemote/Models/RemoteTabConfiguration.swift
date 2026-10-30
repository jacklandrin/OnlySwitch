import Foundation

struct RemoteTabConfiguration: Equatable, Sendable {
    var showsSystemMonitor = true
    var showsSoundMixer = true
    var showsBrightness = true
    var showsCodexUsage = true
    var showsClaudeUsage = true
    var showsAphrodite = true

    var visiblePages: [RemoteAppPage] { RemoteAppPage.allCases.filter(isVisible) }

    func isVisible(_ page: RemoteAppPage) -> Bool {
        switch page {
        case .controls: true
        case .systemMonitor: showsSystemMonitor
        case .soundMixer: showsSoundMixer
        case .brightness: showsBrightness
        case .codexUsage: showsCodexUsage
        case .claudeUsage: showsClaudeUsage
        case .aphrodite: showsAphrodite
        }
    }

    mutating func setVisibility(_ isVisible: Bool, for page: RemoteAppPage) {
        switch page {
        case .controls: break
        case .systemMonitor: showsSystemMonitor = isVisible
        case .soundMixer: showsSoundMixer = isVisible
        case .brightness: showsBrightness = isVisible
        case .codexUsage: showsCodexUsage = isVisible
        case .claudeUsage: showsClaudeUsage = isVisible
        case .aphrodite: showsAphrodite = isVisible
        }
    }
}
