import ComposableArchitecture
import DesktopPet
import DesktopPetSkinKit
import Extensions
import Foundation
import OnlyAgent
import Testing
@testable import AppFeature

@MainActor
struct DesktopPetSkinsFeatureTests {
    let cat = makeSkin(id: UUID(1), name: "Cat")
    let dog = makeSkin(id: UUID(2), name: "Dog")
    let draft = DesktopPetSkinDraft(name: "Sleepy Cat", markup: "<m>")

    // 1
    @Test func taskLoadsSkinsAndSelection() async {
        let skins = [cat, dog]
        let selectedID = dog.id
        let store = TestStore(initialState: DesktopPetSkinsFeature.State()) {
            DesktopPetSkinsFeature()
        } withDependencies: {
            $0.desktopPetSkinLibrary.load = { skins }
            $0.desktopPetSkinLibrary.selectedID = { selectedID }
        }

        await store.send(.task)
        await store.receive(\.loaded) {
            $0.skins = skins
            $0.selectedID = selectedID
        }
    }

    // 2
    @Test(arguments: [UUID(1), nil] as [UUID?])
    func selectingSavesSelectionAndNotifies(id: UUID?) async {
        let selected = LockIsolated<[UUID?]>([])
        let notified = LockIsolated(0)
        var state = DesktopPetSkinsFeature.State()
        state.skins = [cat]
        state.selectedID = id == nil ? cat.id : nil
        let store = TestStore(initialState: state) {
            DesktopPetSkinsFeature()
        } withDependencies: {
            $0.desktopPetSkinLibrary.select = { id in selected.withValue { $0.append(id) } }
            $0.desktopPetSkinNotifier = { notified.withValue { $0 += 1 } }
        }

        await store.send(.selected(id)) {
            $0.selectedID = id
        }
        await store.finish()

        #expect(selected.value == [id])
        #expect(notified.value == 1)
    }

    // 3
    @Test func deletingSelectedSkinReloadsClearsSelectionAndNotifies() async {
        let deleted = LockIsolated<[UUID]>([])
        let notified = LockIsolated(0)
        let remaining = [dog]
        var state = DesktopPetSkinsFeature.State()
        state.skins = [cat, dog]
        state.selectedID = cat.id
        let store = TestStore(initialState: state) {
            DesktopPetSkinsFeature()
        } withDependencies: {
            $0.desktopPetSkinLibrary.delete = { id in
                deleted.withValue { $0.append(id) }
                return remaining
            }
            // The live client clears the selection when the selected skin is deleted.
            $0.desktopPetSkinLibrary.selectedID = { nil }
            $0.desktopPetSkinNotifier = { notified.withValue { $0 += 1 } }
        }

        await store.send(.deleteTapped(cat.id))
        await store.receive(\.loaded) {
            $0.skins = remaining
            $0.selectedID = nil
        }
        await store.finish()

        #expect(deleted.value == [cat.id])
        #expect(notified.value == 1)
    }

    // 4
    @Test(arguments: [true, false])
    func creatingOpensGeneratorWithModelAvailability(isModelSelected: Bool) async {
        let store = TestStore(initialState: DesktopPetSkinsFeature.State()) {
            DesktopPetSkinsFeature()
        } withDependencies: {
            $0.desktopPetSkinGeneration.isModelSelected = { isModelSelected }
        }

        await store.send(.createTapped) {
            $0.generator = DesktopPetSkinsFeature.Generator(isModelSelected: isModelSelected)
        }
    }

    // 5
    @Test func generatingWithBlankDescriptionDoesNothing() async {
        let requested = LockIsolated<[String]>([])
        var state = DesktopPetSkinsFeature.State()
        state.generator = DesktopPetSkinsFeature.Generator(description: "  \n ", isModelSelected: true)
        let draft = self.draft
        let store = TestStore(initialState: state) {
            DesktopPetSkinsFeature()
        } withDependencies: {
            $0.desktopPetSkinGeneration.generate = { description in
                requested.withValue { $0.append(description) }
                return draft
            }
        }

        await store.send(.generator(.generateTapped))
        await store.finish()

        #expect(requested.value.isEmpty)
    }

    // 6
    @Test func generatingStoresDraft() async {
        let requested = LockIsolated<[String]>([])
        var state = DesktopPetSkinsFeature.State()
        state.generator = DesktopPetSkinsFeature.Generator(description: "a sleepy cat", isModelSelected: true)
        let draft = self.draft
        let store = TestStore(initialState: state) {
            DesktopPetSkinsFeature()
        } withDependencies: {
            $0.desktopPetSkinGeneration.generate = { description in
                requested.withValue { $0.append(description) }
                return draft
            }
        }

        await store.send(.generator(.generateTapped)) {
            $0.generator?.isGenerating = true
        }
        await store.receive(\.generator.generated) {
            $0.generator?.isGenerating = false
            $0.generator?.draft = draft
        }

        #expect(requested.value == ["a sleepy cat"])
    }

    // 7
    struct FailureCase: Sendable, CustomTestStringConvertible {
        let error: DesktopPetSkinGenerationError
        let messageKey: String
        let isLocalized: Bool

        var testDescription: String { "\(error)" }
        var expectedMessage: String { isLocalized ? messageKey.localized() : messageKey }
    }

    @Test(arguments: [
        FailureCase(error: .invalid(.missingStates(["eating"])), messageKey: "Desktop Pet Generation Failed", isLocalized: true),
        FailureCase(error: .noMarkup, messageKey: "Desktop Pet Generation Failed", isLocalized: true),
        FailureCase(error: .noModelSelected, messageKey: "Desktop Pet No Model", isLocalized: true),
        FailureCase(error: .refused("not appropriate"), messageKey: "not appropriate", isLocalized: false),
    ])
    func generationFailureShowsMessage(_ failure: FailureCase) async {
        var state = DesktopPetSkinsFeature.State()
        state.generator = DesktopPetSkinsFeature.Generator(
            description: "a sleepy cat", isGenerating: true, isModelSelected: true
        )
        let store = TestStore(initialState: state) {
            DesktopPetSkinsFeature()
        }

        await store.send(.generator(.generated(.failure(failure.error)))) {
            $0.generator?.isGenerating = false
            $0.generator?.errorMessage = failure.expectedMessage
        }
    }

    // 8
    @Test func savingDraftStoresSelectsAndCloses() async {
        let id = UUID(0)
        let now = Date(timeIntervalSinceReferenceDate: 5)
        let saved = LockIsolated<[DesktopPetSkin]>([])
        let selected = LockIsolated<[UUID?]>([])
        let notified = LockIsolated(0)
        var state = DesktopPetSkinsFeature.State()
        state.generator = DesktopPetSkinsFeature.Generator(description: "a sleepy cat", draft: draft)
        let expected = DesktopPetSkin(
            id: id, name: "Sleepy Cat", summary: "a sleepy cat", createdAt: now, contractVersion: 1, markup: "<m>"
        )
        let store = TestStore(initialState: state) {
            DesktopPetSkinsFeature()
        } withDependencies: {
            $0.uuid = .constant(id)
            $0.date.now = now
            $0.desktopPetSkinLibrary.save = { skin in
                saved.withValue { $0.append(skin) }
                return [skin]
            }
            $0.desktopPetSkinLibrary.select = { id in selected.withValue { $0.append(id) } }
            $0.desktopPetSkinNotifier = { notified.withValue { $0 += 1 } }
        }

        await store.send(.generator(.saveTapped)) {
            $0.generator?.isGenerating = true
        }
        await store.receive(\.saved) {
            $0.skins = [expected]
            $0.selectedID = id
            $0.generator = nil
        }
        await store.finish()

        #expect(saved.value == [expected])
        #expect(selected.value == [id])
        #expect(notified.value == 1)
    }

    @Test func savingUnnamedDraftNamesItFromTheDescription() async {
        let id = UUID(0)
        let now = Date(timeIntervalSinceReferenceDate: 5)
        let description = "a sleepy orange cat with a long striped scarf"
        let saved = LockIsolated<[DesktopPetSkin]>([])
        var state = DesktopPetSkinsFeature.State()
        state.generator = DesktopPetSkinsFeature.Generator(
            description: description, draft: DesktopPetSkinDraft(name: "", markup: "<m>")
        )
        let expected = DesktopPetSkin(
            id: id, name: String(description.prefix(20)), summary: description, createdAt: now,
            contractVersion: DesktopPetSkinContract.version, markup: "<m>"
        )
        let store = TestStore(initialState: state) {
            DesktopPetSkinsFeature()
        } withDependencies: {
            $0.uuid = .constant(id)
            $0.date.now = now
            $0.desktopPetSkinLibrary.save = { skin in
                saved.withValue { $0.append(skin) }
                return [skin]
            }
            $0.desktopPetSkinLibrary.select = { _ in }
            $0.desktopPetSkinNotifier = {}
        }

        await store.send(.generator(.saveTapped)) {
            $0.generator?.isGenerating = true
        }
        await store.receive(\.saved) {
            $0.skins = [expected]
            $0.selectedID = id
            $0.generator = nil
        }
        await store.finish()

        #expect(saved.value == [expected])
    }

    // 9
    @Test func savingWhenLibraryIsFullShowsMessage() async {
        let selected = LockIsolated<[UUID?]>([])
        let notified = LockIsolated(0)
        var state = DesktopPetSkinsFeature.State()
        state.skins = [cat]
        state.generator = DesktopPetSkinsFeature.Generator(description: "a sleepy cat", draft: draft)
        let store = TestStore(initialState: state) {
            DesktopPetSkinsFeature()
        } withDependencies: {
            $0.uuid = .constant(UUID(0))
            $0.date.now = Date(timeIntervalSinceReferenceDate: 5)
            $0.desktopPetSkinLibrary.save = { _ in throw DesktopPetSkinLibraryError.full }
            $0.desktopPetSkinLibrary.select = { id in selected.withValue { $0.append(id) } }
            $0.desktopPetSkinNotifier = { notified.withValue { $0 += 1 } }
        }

        await store.send(.generator(.saveTapped)) {
            $0.generator?.isGenerating = true
        }
        await store.receive(\.saveFailed) {
            $0.generator?.isGenerating = false
            $0.generator?.errorMessage = "Desktop Pet Skins Full".localized()
        }
        await store.finish()

        #expect(selected.value.isEmpty)
        #expect(notified.value == 0)
    }

    // 10
    @Test func cancellingStopsGenerationAndClosesSheet() async {
        var state = DesktopPetSkinsFeature.State()
        state.generator = DesktopPetSkinsFeature.Generator(description: "a sleepy cat", isModelSelected: true)
        let store = TestStore(initialState: state) {
            DesktopPetSkinsFeature()
        } withDependencies: {
            $0.desktopPetSkinGeneration.generate = { _ in try await Task.never() }
        }

        await store.send(.generator(.generateTapped)) {
            $0.generator?.isGenerating = true
        }
        await store.send(.generator(.cancelTapped)) {
            $0.generator = nil
        }
        // Fails if the generation effect is still running, i.e. was not cancelled.
        await store.finish()
    }
}

private func makeSkin(id: UUID, name: String) -> DesktopPetSkin {
    DesktopPetSkin(
        id: id, name: name, summary: name.lowercased(), createdAt: Date(timeIntervalSinceReferenceDate: 0),
        contractVersion: DesktopPetSkinContract.version, markup: "<div id=\"pet\"></div>"
    )
}
