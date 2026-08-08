import Foundation
import RemoteCore
import Switches

struct RemoteShortcutProcessClient: Sendable {
    private let runProcess: @Sendable (URL, [String]) async throws -> Void

    init(_ runProcess: @escaping @Sendable (URL, [String]) async throws -> Void) {
        self.runProcess = runProcess
    }

    func runShortcut(named name: String) async throws {
        try await runProcess(
            URL(fileURLWithPath: "/usr/bin/shortcuts"),
            ["run", name]
        )
    }

    static let live = Self { executableURL, arguments in
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationReason == .exit, process.terminationStatus == 0 else {
                throw RemoteProtocolError(
                    code: .executionFailed,
                    message: "The Shortcut could not be executed"
                )
            }
        }.value
    }
}

extension RemoteCommandRouter {
    @MainActor
    static var live: RemoteCommandRouter {
        RemoteCommandRouter(
            resolveBuiltIn: { rawValue in
                SwitchType(rawValue: rawValue)?.getNewSwitchInstance()
            },
            installedShortcutNames: {
                Set(await ShortcutsSettingVM.shared.getAllInstalledShortcutName() ?? [])
            },
            runShortcut: { name in
                try await RemoteShortcutProcessClient.live.runShortcut(named: name)
            },
            resolveEvolution: { id in
                try? EvolutionCommandEntity.fetchRequest(by: id).flatMap(EvolutionAdapter.toEvolutionItem)
            },
            runEvolution: { evolution, action in
                let service = EvolutionCommandService.liveValue
                switch action {
                case let .setState(isOn):
                    _ = try await service.executeCommand(isOn ? evolution.onCommand : evolution.offCommand)
                case .trigger:
                    _ = try await service.executeCommand(evolution.singleCommand)
                }
            },
            cache: RecentRequestCache(capacity: 512)
        )
    }
}
