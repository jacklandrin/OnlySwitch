import ComposableArchitecture
import Foundation
import Testing
@testable import AppFeature

@MainActor
struct EvolutionReducerTests {
    nonisolated private static let a = EvolutionItem(
        id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!,
        name: "A",
        active: true,
        controlType: .Button,
        singleCommand: EvolutionCommand(executeType: .shell, commandType: .single, commandString: "echo a")
    )
    nonisolated private static let b = EvolutionItem(
        id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000000")!,
        name: "B",
        controlType: .Button,
        singleCommand: EvolutionCommand(executeType: .shell, commandType: .single, commandString: "echo b")
    )

    private func makeStore(
        state: EvolutionReducer.State = .init(),
        items: [EvolutionItem] = [a, b],
        removed: LockIsolated<[UUID]> = .init([]),
        activated: LockIsolated<[UUID: Bool]> = .init([:])
    ) -> TestStoreOf<EvolutionReducer> {
        let store = TestStore(initialState: state) {
            EvolutionReducer()
        } withDependencies: {
            $0.evolutionListService = EvolutionListService(
                loadEvolutionList: { items },
                removeItem: { id in removed.withValue { $0.append(id) } },
                setActive: { id, active in activated.withValue { $0[id] = active } }
            )
            $0.evolutionGalleryService.fetchGalleryList = { [] }
            $0.evolutionGalleryService.checkInstallation = { _ in false }
            $0.onlyAgentLauncher.isAvailable = { false }
            $0.defaultAppStorage = UserDefaults(suiteName: "EvolutionReducerTests-\(UUID().uuidString)")!
        }
        store.exhaustivity = .off
        return store
    }

    @Test
    func loadSelectsFirstItemAndShowsItsEditor() async {
        let store = makeStore()
        await store.send(.task)
        await store.receive(\.loadList)
        #expect(store.state.hasLoaded)
        #expect(store.state.evolutionList.ids.elements == [Self.a.id, Self.b.id])
        #expect(store.state.selectedID == Self.a.id)
        #expect(store.state.detail?.id == Self.a.id)
        #expect(store.state.evolutionList[id: Self.a.id]?.evolution.active == true)
    }

    @Test
    func emptyListHasNoDetail() async {
        let store = makeStore(items: [])
        await store.send(.task)
        await store.receive(\.loadList)
        #expect(store.state.selectedID == nil)
        #expect(store.state.detail == nil)
    }

    @Test
    func switchingAwayFromDirtyEditorAsksFirst() async {
        let store = makeStore()
        await store.send(.task)
        await store.receive(\.loadList)
        await store.send(.detail(.changeName("Edited")))
        await store.send(.rowTapped(Self.b.id))
        #expect(store.state.pendingSelection == .item(Self.b.id))
        #expect(store.state.selectedID == Self.a.id)

        await store.send(.discardChangesCancelled)
        #expect(store.state.detail?.evolution.name == "Edited")

        await store.send(.rowTapped(Self.b.id))
        await store.send(.discardChangesConfirmed)
        #expect(store.state.selectedID == Self.b.id)
        #expect(store.state.detail?.evolution.name == "B")
    }

    @Test
    func cleanEditorSwitchesImmediately() async {
        let store = makeStore()
        await store.send(.task)
        await store.receive(\.loadList)
        await store.send(.rowTapped(Self.b.id))
        #expect(store.state.pendingSelection == nil)
        #expect(store.state.detail?.id == Self.b.id)
    }

    @Test
    func newOpensBlankEditorAndSurvivesRefresh() async {
        let store = makeStore()
        await store.send(.task)
        await store.receive(\.loadList)
        await store.send(.newTapped)
        #expect(store.state.detail?.isNew == true)
        #expect(store.state.selectedID == nil)
        await store.send(.refresh)
        await store.receive(\.loadList)
        #expect(store.state.detail?.isNew == true)
    }

    @Test
    func refreshKeepsUnsavedEdits() async {
        let store = makeStore()
        await store.send(.task)
        await store.receive(\.loadList)
        await store.send(.detail(.changeName("Edited")))
        await store.send(.refresh)
        await store.receive(\.loadList)
        #expect(store.state.detail?.evolution.name == "Edited")
    }

    @Test
    func deleteRequiresConfirmation() async {
        let removed = LockIsolated<[UUID]>([])
        let store = makeStore(removed: removed)
        await store.send(.task)
        await store.receive(\.loadList)
        await store.send(.deleteTapped(Self.a.id))
        #expect(store.state.pendingDeletion?.id == Self.a.id)
        #expect(removed.value.isEmpty)
        await store.send(.deleteCancelled)
        #expect(removed.value.isEmpty)

        await store.send(.deleteTapped(Self.a.id))
        await store.send(.deleteConfirmed)
        await store.receive(\.deleteFinished)
        #expect(removed.value == [Self.a.id])
        await store.skipReceivedActions()
    }

    @Test
    func savingNewEvolutionSelectsAndActivatesIt() async {
        let activated = LockIsolated<[UUID: Bool]>([:])
        let store = makeStore(activated: activated)
        await store.send(.task)
        await store.receive(\.loadList)
        await store.send(.newTapped)
        var item = EvolutionItem(name: "New", controlType: .Button)
        item.singleCommand = EvolutionCommand(commandType: .single, commandString: "x")
        await store.send(.detail(.delegate(.saved(item))))
        #expect(store.state.selectedID == item.id)
        #expect(store.state.detail?.isNew == false)
        await store.skipReceivedActions()
        await store.finish()
        #expect(activated.value[item.id] == true)
    }

    @Test
    func togglingRowUpdatesMenuVisibility() async {
        let activated = LockIsolated<[UUID: Bool]>([:])
        let store = makeStore(activated: activated)
        await store.send(.task)
        await store.receive(\.loadList)
        await store.send(.row(.element(id: Self.b.id, action: .setActive(true))))
        await store.finish()
        #expect(store.state.evolutionList[id: Self.b.id]?.evolution.active == true)
        #expect(activated.value[Self.b.id] == true)
    }
}
