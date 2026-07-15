import RemoteCore
import Switches

extension RemoteCommandRouter {
    @MainActor
    static var live: RemoteCommandRouter {
        RemoteCommandRouter(
            resolveBuiltIn: { rawValue in
                SwitchType(rawValue: rawValue)?.getNewSwitchInstance()
            },
            runShortcut: { name in
                _ = try await ShorcutsCMD.runShortcut(name: name).runAppleScript(isShellCMD: true)
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
