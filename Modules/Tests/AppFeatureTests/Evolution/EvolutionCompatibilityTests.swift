import ComposableArchitecture
import Foundation
import PrivilegedHelperCore
import Testing
@testable import AppFeature

/// Previously saved Evolutions must keep running exactly as before: the
/// editor never rewrites a command the user didn't touch.
@MainActor
struct EvolutionCompatibilityTests {
    static func legacySwitch() -> EvolutionItem {
        EvolutionItem(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "Legacy",
            controlType: .Switch,
            onCommand: EvolutionCommand(executeType: .shell, commandType: .on, commandString: "echo on\r\necho done"),
            offCommand: EvolutionCommand(executeType: .applescript, commandType: .off, commandString: "tell application \"Finder\" to quit"),
            statusCommand: EvolutionCommand(executeType: .shell, commandType: .status, commandString: "echo 1", trueCondition: "1")
        )
    }

    static func legacyButton() -> EvolutionItem {
        EvolutionItem(
            id: UUID(uuidString: "66666666-2222-3333-4444-555555555555")!,
            name: "Legacy Button",
            iconName: "moon.circle",
            controlType: .Button,
            singleCommand: EvolutionCommand(executeType: .applescript, commandType: .single, commandString: "beep\n")
        )
    }

    @Test
    func savingUneditedLegacySwitchKeepsCommandsByteForByte() async {
        let item = Self.legacySwitch()
        let saved = LockIsolated<EvolutionItem?>(nil)
        let store = TestStore(initialState: EvolutionEditorReducer.State(evolution: item)) {
            EvolutionEditorReducer()
        } withDependencies: {
            $0.evolutionCommandService.saveCommand = { saved.setValue($0) }
        }
        store.exhaustivity = .off
        await store.send(.save)
        await store.finish()
        #expect(saved.value?.id == item.id)
        #expect(saved.value?.name == item.name)
        #expect(saved.value?.onCommand?.commandString == "echo on\r\necho done")
        #expect(saved.value?.onCommand?.executeType == .shell)
        #expect(saved.value?.offCommand?.commandString == "tell application \"Finder\" to quit")
        #expect(saved.value?.offCommand?.executeType == .applescript)
        #expect(saved.value?.statusCommand?.commandString == "echo 1")
        #expect(saved.value?.statusCommand?.trueCondition == "1")
    }

    @Test
    func savingUneditedLegacyButtonKeepsCommandAndIcon() async {
        let item = Self.legacyButton()
        let saved = LockIsolated<EvolutionItem?>(nil)
        let store = TestStore(initialState: EvolutionEditorReducer.State(evolution: item)) {
            EvolutionEditorReducer()
        } withDependencies: {
            $0.evolutionCommandService.saveCommand = { saved.setValue($0) }
        }
        store.exhaustivity = .off
        await store.send(.save)
        await store.finish()
        #expect(saved.value?.singleCommand?.commandString == "beep\n")
        #expect(saved.value?.singleCommand?.executeType == .applescript)
        #expect(saved.value?.iconName == "moon.circle")
        #expect(saved.value?.controlType == .Button)
    }

    @Test
    func savingPreservesCuratedPrivilegedOperation() async {
        var item = Self.legacySwitch()
        item.privilegedOperation = .clamshellSleepDisabled
        let saved = LockIsolated<EvolutionItem?>(nil)
        let store = TestStore(initialState: EvolutionEditorReducer.State(evolution: item)) {
            EvolutionEditorReducer()
        } withDependencies: {
            $0.evolutionCommandService.saveCommand = { saved.setValue($0) }
        }
        store.exhaustivity = .off
        await store.send(.save)
        await store.finish()
        #expect(saved.value?.privilegedOperation == .clamshellSleepDisabled)
    }
}
