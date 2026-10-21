import Foundation

struct RemoteTabConfiguration: Equatable, Sendable {
    var showsSystemMonitor = true
    var showsCodexUsage = true
    var showsClaudeUsage = true

    var visiblePages: [RemoteAppPage] {
        [.controls]
            + (showsSystemMonitor ? [.systemMonitor] : [])
            + (showsCodexUsage ? [.codexUsage] : [])
            + (showsClaudeUsage ? [.claudeUsage] : [])
            + [.aphrodite]
    }

    mutating func setVisibility(_ isVisible: Bool, for page: RemoteAppPage) {
        switch page {
        case .systemMonitor: showsSystemMonitor = isVisible
        case .codexUsage: showsCodexUsage = isVisible
        case .claudeUsage: showsClaudeUsage = isVisible
        case .controls, .aphrodite: break
        }
    }
}
