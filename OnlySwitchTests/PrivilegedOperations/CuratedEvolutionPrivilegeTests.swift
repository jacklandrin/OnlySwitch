import Dependencies
import Synchronization
import Testing
@testable import OnlySwitch

struct CuratedEvolutionPrivilegeTests {
    private struct Invocation: Equatable, Sendable {
        let operation: PrivilegedOperation
        let enabled: Bool
    }

    @Test
    func clamshellCatalogueEntryGetsTheFixedPrivilegedOperation() {
        let item = EvolutionGalleryAdaptor.convertToGalleryItem(from: clamshellModel())

        #expect(item.evolution.privilegedOperation == .clamshellSleepDisabled)
    }

    @Test
    func onlyTheFixedCatalogueIdentifierCanDeclareTheClamshellOperation() {
        var model = clamshellModel()
        model.id = UUID().uuidString

        let item = EvolutionGalleryAdaptor.convertToGalleryItem(from: model)

        #expect(item.evolution.privilegedOperation == nil)
    }

    @Test(arguments: [true, false])
    func curatedClamshellUsesTheTypedHelper(enabled: Bool) async throws {
        let invocations = Mutex<[Invocation]>([])
        let normalCommands = Mutex<[String]>([])
        let service = service(recording: normalCommands)
        let client = recordingClient(invocations: invocations)
        let item = EvolutionGalleryAdaptor.convertToGalleryItem(from: clamshellModel()).evolution

        let result = try await withDependencies {
            $0.privilegedOperationClient = client
        } operation: {
            try await service.executeSwitch(item, enabled: enabled)
        }

        #expect(result.isEmpty)
        #expect(invocations.withLock { $0 } == [.init(operation: .clamshellSleepDisabled, enabled: enabled)])
        #expect(normalCommands.withLock { $0 }.isEmpty)
    }

    @Test(arguments: ["sudo pmset -a disablesleep 1", "do shell script \"pmset -a disablesleep 1\"", "/bin/sh -c 'whoami'"])
    func customCommandsNeverReachTheHelper(command: String) async throws {
        let invocations = Mutex<[Invocation]>([])
        let normalCommands = Mutex<[String]>([])
        let service = service(recording: normalCommands)
        let client = recordingClient(invocations: invocations)
        let item = EvolutionItem(
            name: "Custom",
            controlType: .Switch,
            onCommand: .init(commandType: .on, commandString: command)
        )

        let result = try await withDependencies {
            $0.privilegedOperationClient = client
        } operation: {
            try await service.executeSwitch(item, enabled: true)
        }

        #expect(result == "normal")
        #expect(item.privilegedOperation == nil)
        #expect(invocations.withLock { $0 }.isEmpty)
        #expect(normalCommands.withLock { $0 } == [command])
    }

    @Test
    func forgedPrivilegedMetadataNeverReachesTheHelper() async throws {
        let invocations = Mutex<[Invocation]>([])
        let normalCommands = Mutex<[String]>([])
        let service = service(recording: normalCommands)
        let client = recordingClient(invocations: invocations)
        let command = "echo normal"
        let item = EvolutionItem(
            name: "Forged",
            controlType: .Switch,
            onCommand: .init(commandType: .on, commandString: command),
            privilegedOperation: .clamshellSleepDisabled
        )

        let result = try await withDependencies {
            $0.privilegedOperationClient = client
        } operation: {
            try await service.executeSwitch(item, enabled: true)
        }

        #expect(result == "normal")
        #expect(invocations.withLock { $0 }.isEmpty)
        #expect(normalCommands.withLock { $0 } == [command])
    }

    private func service(recording commands: Mutex<[String]>) -> EvolutionCommandService {
        EvolutionCommandService(
            executeCommand: { command in
                commands.withLock { $0.append(command?.commandString ?? "") }
                return "normal"
            },
            saveCommand: { _ in },
            saveIcon: { _, _ in }
        )
    }

    private func recordingClient(invocations: Mutex<[Invocation]>) -> PrivilegedOperationClient {
        PrivilegedOperationClient(
            status: { .enabled },
            installFromInteractiveUI: {},
            removeFromInteractiveUI: {},
            perform: { operation, enabled in
                invocations.withLock { $0.append(.init(operation: operation, enabled: enabled)) }
            },
            openSystemSettings: {}
        )
    }

    private func clamshellModel() -> EvolutionGalleryModel {
        EvolutionGalleryModel(
            id: "0AD2A1A8-E0BA-4F6A-9E28-2E2B06143C8D",
            name: "Clamshell",
            icon_name: "lightbulb.circle",
            type: "Switch",
            description: "",
            author: "OnlySwitch",
            on_command: .init(type: "shell", command: "true", true_condition: nil),
            off_command: .init(type: "shell", command: "true", true_condition: nil),
            check_command: .init(type: "shell", command: "pmset -g", true_condition: "true"),
            single_command: nil,
            privileged_operation: PrivilegedOperation.clamshellSleepDisabled.rawValue
        )
    }
}
