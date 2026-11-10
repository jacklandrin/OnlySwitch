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
        await store.send(.changeName("Renamed"))
        await store.send(.save)
        await store.finish()
        #expect(saved.value?.id == item.id)
        #expect(saved.value?.name == "Renamed")
        #expect(saved.value?.onCommand?.commandString == "echo on\r\necho done")
        #expect(saved.value?.onCommand?.executeType == .shell)
        #expect(saved.value?.offCommand?.commandString == "tell application \"Finder\" to quit")
        #expect(saved.value?.offCommand?.executeType == .applescript)
        #expect(saved.value?.statusCommand?.commandString == "echo 1")
        #expect(saved.value?.statusCommand?.trueCondition == "1")
        // Persistence only accepts tested on/off commands; unchanged ones count as tested.
        #expect(saved.value?.onCommand?.debugStatus == .success)
        #expect(saved.value?.offCommand?.debugStatus == .success)
    }

    @Test
    func uneditedItemIsNotDirtyAndCannotBeSaved() async {
        let store = TestStore(initialState: EvolutionEditorReducer.State(evolution: Self.legacySwitch())) {
            EvolutionEditorReducer()
        }
        #expect(!store.state.isDirty)
        #expect(store.state.missingRequirements.isEmpty)
        // saveCommand is unimplemented: calling it fails the test.
        await store.send(.save)
    }

    @Test
    func legacyEmptyOnOutputIsAcceptedWhileUnchanged() {
        var item = Self.legacySwitch()
        item.statusCommand?.trueCondition = ""
        let state = EvolutionEditorReducer.State(evolution: item)
        #expect(state.missingRequirements.isEmpty)
    }

    @Test
    func editedCommandMustBeTestedAgain() async {
        let store = TestStore(initialState: EvolutionEditorReducer.State(evolution: Self.legacySwitch())) {
            EvolutionEditorReducer()
        }
        store.exhaustivity = .off
        await store.send(.commandAction(.element(id: .off, action: .editCommand("echo off"))))
        #expect(store.state.missingRequirements == [.test(.off)])
        #expect(!store.state.canSave)
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
        await store.send(.changeName("Renamed"))
        await store.send(.save)
        await store.finish()
        #expect(saved.value?.singleCommand?.commandString == "beep\n")
        #expect(saved.value?.singleCommand?.executeType == .applescript)
        #expect(saved.value?.iconName == "moon.circle")
        #expect(saved.value?.controlType == .Button)
        #expect(saved.value?.singleCommand?.debugStatus == .success)
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
        await store.send(.changeName("Renamed"))
        await store.send(.save)
        await store.finish()
        #expect(saved.value?.privilegedOperation == .clamshellSleepDisabled)
    }
}
