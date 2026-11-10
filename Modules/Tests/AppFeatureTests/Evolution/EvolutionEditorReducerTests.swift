import ComposableArchitecture
import Foundation
import OnlyAgent
import Testing
@testable import AppFeature

@MainActor
struct EvolutionEditorReducerTests {
    nonisolated private static let switchScripts = GeneratedEvolutionScripts(
        name: "Dark",
        turnOn: GeneratedScript(kind: .applescript, code: "set dark to true"),
        turnOff: GeneratedScript(kind: .shell, code: "echo \"off\" \\ done"),
        status: GeneratedScript(kind: .shell, code: "echo 1"),
        statusOnOutput: "1",
        notes: "Needs Automation."
    )

    @Test
    func newSwitchListsEveryRequirement() {
        let state = EvolutionEditorReducer.State()
        #expect(state.isNew)
        #expect(state.missingRequirements == [.name, .script(.on), .script(.off), .script(.status), .statusOnOutput])
        #expect(!state.canSave)
    }

    @Test
    func newButtonNeedsNameScriptAndTest() async {
        let store = TestStore(initialState: EvolutionEditorReducer.State()) { EvolutionEditorReducer() }
        store.exhaustivity = .off
        await store.send(.changeType(.Button))
        #expect(store.state.missingRequirements == [.name, .script(.single)])
        await store.send(.changeName("Hello"))
        await store.send(.commandAction(.element(id: .single, action: .editCommand("beep"))))
        #expect(store.state.missingRequirements == [.test(.single)])
    }

    @Test
    func typeToggleKeepsEditsOfBothTypes() async {
        let store = TestStore(initialState: EvolutionEditorReducer.State()) { EvolutionEditorReducer() }
        store.exhaustivity = .off
        await store.send(.commandAction(.element(id: .on, action: .editCommand("echo on"))))
        await store.send(.changeType(.Button))
        #expect(store.state.commandStates.ids == [.single])
        await store.send(.commandAction(.element(id: .single, action: .editCommand("beep"))))
        await store.send(.changeType(.Switch))
        #expect(store.state.commandStates[id: .on]?.command.commandString == "echo on")
        #expect(store.state.stashedCommandStates[id: .single]?.command.commandString == "beep")
    }

    @Test
    func passingTestUnblocksSaveAndSaveDelegates() async {
        let saved = LockIsolated<EvolutionItem?>(nil)
        let store = TestStore(initialState: EvolutionEditorReducer.State()) {
            EvolutionEditorReducer()
        } withDependencies: {
            $0.evolutionCommandService.executeCommand = { _ in "ok" }
            $0.evolutionCommandService.saveCommand = { saved.setValue($0) }
        }
        store.exhaustivity = .off
        await store.send(.changeType(.Button))
        await store.send(.changeName("Beep"))
        await store.send(.commandAction(.element(id: .single, action: .editCommand("beep"))))
        await store.send(.commandAction(.element(id: .single, action: .testTapped)))
        await store.receive(\.commandAction)
        #expect(store.state.commandStates[id: .single]?.command.debugStatus == .success)
        #expect(store.state.canSave)
        await store.send(.save)
        await store.receive(\.saveFinished)
        await store.receive(\.delegate.saved)
        #expect(saved.value?.singleCommand?.commandString == "beep")
        #expect(saved.value?.singleCommand?.debugStatus == .success)
    }

    @Test
    func failingTestShowsMessageAndBlocksSave() async {
        let store = TestStore(initialState: EvolutionEditorReducer.State(evolution: EvolutionCompatibilityTests.legacyButton())) {
            EvolutionEditorReducer()
        } withDependencies: {
            $0.evolutionCommandService.executeCommand = { _ in throw EvolutionError.wrongCommand }
        }
        store.exhaustivity = .off
        await store.send(.commandAction(.element(id: .single, action: .testTapped)))
        await store.receive(\.commandAction)
        #expect(store.state.commandStates[id: .single]?.errorMessage != nil)
        #expect(store.state.missingRequirements == [.test(.single)])
    }

    @Test
    func editingResetsTestResult() async {
        var state = EvolutionEditorReducer.State()
        state.commandStates[id: .on]?.command.debugStatus = .success
        state.commandStates[id: .on]?.lastOutput = "x"
        let store = TestStore(initialState: state) { EvolutionEditorReducer() }
        store.exhaustivity = .off
        await store.send(.commandAction(.element(id: .on, action: .editCommand("new"))))
        #expect(store.state.commandStates[id: .on]?.command.debugStatus == .unknow)
        #expect(store.state.commandStates[id: .on]?.lastOutput == nil)
    }

    @Test
    func useLastOutputCopiesExactOutput() async {
        var state = EvolutionEditorReducer.State()
        state.commandStates[id: .status]?.lastOutput = "true"
        let store = TestStore(initialState: state) { EvolutionEditorReducer() }
        store.exhaustivity = .off
        await store.send(.commandAction(.element(id: .status, action: .useLastOutput)))
        #expect(store.state.commandStates[id: .status]?.command.trueCondition == "true")
    }

    @Test
    func revertRestoresSavedVersion() async {
        let store = TestStore(initialState: EvolutionEditorReducer.State(evolution: EvolutionCompatibilityTests.legacySwitch())) {
            EvolutionEditorReducer()
        }
        store.exhaustivity = .off
        await store.send(.changeName("X"))
        await store.send(.commandAction(.element(id: .on, action: .editCommand("changed"))))
        #expect(store.state.isDirty)
        await store.send(.revert)
        #expect(!store.state.isDirty)
        #expect(store.state.commandStates[id: .on]?.command.commandString == "echo on\r\necho done")
    }

    @Test
    func generationFillsEmptyScriptsWithoutRunningThem() async {
        let store = TestStore(initialState: EvolutionEditorReducer.State(generationAvailable: true)) {
            EvolutionEditorReducer()
        } withDependencies: {
            $0.evolutionScriptGenerationClient.isModelSelected = { true }
            $0.evolutionScriptGenerationClient.generate = { description, target in
                #expect(description == "dark mode")
                #expect(target == .switchControl)
                return Self.switchScripts
            }
            // executeCommand stays unimplemented: running any script fails the test.
        }
        store.exhaustivity = .off
        await store.send(.generation(.promptChanged("  dark mode ")))
        await store.send(.generation(.generateTapped))
        await store.receive(\.generation.generated)
        #expect(store.state.evolution.name == "Dark")
        #expect(store.state.commandStates[id: .on]?.command.executeType == .applescript)
        #expect(store.state.commandStates[id: .on]?.command.commandString == "set dark to true")
        // Shell code is stored as the contents of `do shell script "…"`.
        #expect(store.state.commandStates[id: .off]?.command.commandString == "echo \\\"off\\\" \\\\ done")
        #expect(store.state.commandStates[id: .off]?.command.executeType == .shell)
        #expect(store.state.commandStates[id: .status]?.command.trueCondition == "1")
        #expect(store.state.commandStates.allSatisfy { $0.command.debugStatus == .unknow })
        #expect(store.state.generation.notes == "Needs Automation.")
        #expect(store.state.missingRequirements == [.test(.on), .test(.off)])
    }

    @Test
    func generationKeepsExistingName() async {
        var state = EvolutionEditorReducer.State(generationAvailable: true)
        state.evolution.name = "Mine"
        let store = TestStore(initialState: state) { EvolutionEditorReducer() }
        store.exhaustivity = .off
        await store.send(.generation(.generated(.success(Self.switchScripts), .switchControl)))
        #expect(store.state.evolution.name == "Mine")
    }

    @Test
    func generationAsksBeforeReplacingExistingScripts() async {
        let store = TestStore(
            initialState: EvolutionEditorReducer.State(evolution: EvolutionCompatibilityTests.legacySwitch(), generationAvailable: true)
        ) {
            EvolutionEditorReducer()
        }
        store.exhaustivity = .off
        await store.send(.generation(.generated(.success(Self.switchScripts), .switchControl)))
        #expect(store.state.generation.pendingResult?.scripts == Self.switchScripts)
        #expect(store.state.commandStates[id: .on]?.command.commandString == "echo on\r\necho done")
        await store.send(.generation(.cancelReplace))
        #expect(store.state.generation.pendingResult == nil)
        #expect(store.state.commandStates[id: .on]?.command.commandString == "echo on\r\necho done")

        await store.send(.generation(.generated(.success(Self.switchScripts), .switchControl)))
        await store.send(.generation(.confirmReplace))
        #expect(store.state.commandStates[id: .on]?.command.commandString == "set dark to true")
    }

    @Test
    func generationResultForOtherTypeGoesToStash() async {
        let store = TestStore(initialState: EvolutionEditorReducer.State(generationAvailable: true)) { EvolutionEditorReducer() }
        store.exhaustivity = .off
        let button = GeneratedEvolutionScripts(button: GeneratedScript(kind: .applescript, code: "beep"))
        await store.send(.generation(.generated(.success(button), .button)))
        #expect(store.state.commandStates[id: .on]?.command.commandString == "")
        #expect(store.state.stashedCommandStates[id: .single]?.command.commandString == "beep")
    }

    @Test
    func generateWithoutModelShowsError() async {
        var state = EvolutionEditorReducer.State(generationAvailable: true)
        state.generation.prompt = "x"
        let store = TestStore(initialState: state) {
            EvolutionEditorReducer()
        } withDependencies: {
            $0.evolutionScriptGenerationClient.isModelSelected = { false }
        }
        store.exhaustivity = .off
        await store.send(.generation(.generateTapped))
        #expect(store.state.generation.error == .noModelSelected)
        #expect(!store.state.generation.isGenerating)
    }

    @Test
    func generateIgnoredWhenUnavailableOrBlank() async {
        let store = TestStore(initialState: EvolutionEditorReducer.State(generationAvailable: false)) { EvolutionEditorReducer() }
        await store.send(.generation(.promptChanged("x"))) { $0.generation.prompt = "x" }
        await store.send(.generation(.generateTapped))
    }

    @Test
    func generationFailureIsShown() async {
        var state = EvolutionEditorReducer.State(generationAvailable: true)
        state.generation.prompt = "x"
        let store = TestStore(initialState: state) {
            EvolutionEditorReducer()
        } withDependencies: {
            $0.evolutionScriptGenerationClient.isModelSelected = { true }
            $0.evolutionScriptGenerationClient.generate = { _, _ in throw EvolutionScriptGenerationError.incomplete }
        }
        store.exhaustivity = .off
        await store.send(.generation(.generateTapped))
        await store.receive(\.generation.generated)
        #expect(store.state.generation.error == .incomplete)
        #expect(!store.state.generation.isGenerating)
    }

    @Test
    func selectingIconDoesNotSaveImmediately() async {
        let store = TestStore(initialState: EvolutionEditorReducer.State(evolution: EvolutionCompatibilityTests.legacySwitch())) {
            EvolutionEditorReducer()
        }
        store.exhaustivity = .off
        await store.send(.selectIcon("moon.circle"))
        #expect(store.state.evolution.iconName == "moon.circle")
        #expect(store.state.isDirty)
        #expect(store.state.canSave)
    }
}
