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

    @Test func vanishedSelectionFallsBackToBuiltIn() async {
        let skins = [cat]
        let store = TestStore(initialState: DesktopPetSkinsFeature.State()) {
            DesktopPetSkinsFeature()
        } withDependencies: {
            $0.desktopPetSkinLibrary.load = { skins }
            $0.desktopPetSkinLibrary.selectedID = { UUID(9) }
        }

        await store.send(.task)
        await store.receive(\.loaded) {
            $0.skins = skins
            $0.selectedID = nil
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
            $0.desktopPetSkinGeneration.edit = { _, _ in
                Issue.record("edit must not be called without a draft")
                return draft
            }
        }

        await store.send(.generator(.generateTapped)) {
            $0.generator?.isGenerating = true
        }
        await store.receive(\.generator.generated) {
            $0.generator?.isGenerating = false
            $0.generator?.draft = draft
            $0.generator?.summary = "a sleepy cat"
            $0.generator?.description = ""
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

        await store.send(.generator(.generated(.failure(failure.error), request: "a sleepy cat"))) {
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
        state.generator = DesktopPetSkinsFeature.Generator(draft: draft, summary: "a sleepy cat")
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

    @Test func savingUnnamedDraftNamesItFromTheSummary() async {
        let id = UUID(0)
        let now = Date(timeIntervalSinceReferenceDate: 5)
        let summary = "a sleepy orange cat with a long striped scarf\nadd a hat"
        let saved = LockIsolated<[DesktopPetSkin]>([])
        var state = DesktopPetSkinsFeature.State()
        state.generator = DesktopPetSkinsFeature.Generator(
            description: "unsent text", draft: DesktopPetSkinDraft(name: "", markup: "<m>"), summary: summary
        )
        let expected = DesktopPetSkin(
            id: id, name: String(summary.prefix(20)), summary: summary, createdAt: now,
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
        state.generator = DesktopPetSkinsFeature.Generator(draft: draft, summary: "a sleepy cat")
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

    // MARK: - Editing with AI

    @Test(arguments: [true, false])
    func editingKnownSkinOpensGeneratorWithItsDraftAndSummary(isModelSelected: Bool) async {
        var state = DesktopPetSkinsFeature.State()
        state.skins = [cat, dog]
        let dog = self.dog
        let store = TestStore(initialState: state) {
            DesktopPetSkinsFeature()
        } withDependencies: {
            $0.desktopPetSkinGeneration.isModelSelected = { isModelSelected }
        }

        await store.send(.editTapped(dog.id)) {
            var generator = DesktopPetSkinsFeature.Generator(
                isModelSelected: isModelSelected, editingSkinID: dog.id, summary: dog.summary
            )
            generator.draft = DesktopPetSkinDraft(name: dog.name, markup: dog.markup)
            $0.generator = generator
        }
    }

    @Test func editingUnknownSkinDoesNothing() async {
        var state = DesktopPetSkinsFeature.State()
        state.skins = [cat]
        let store = TestStore(initialState: state) {
            DesktopPetSkinsFeature()
        } withDependencies: {
            $0.desktopPetSkinGeneration.isModelSelected = { true }
        }

        await store.send(.editTapped(UUID(9)))
    }

    @Test func generatingWithDraftEditsItAndAppendsTheRequest() async {
        let edits = LockIsolated<[EditCall]>([])
        let base = DesktopPetSkinDraft(name: "Dog", markup: "<dog>")
        let edited = DesktopPetSkinDraft(name: "Wizard Dog", markup: "<wizard-dog>")
        var state = DesktopPetSkinsFeature.State()
        state.generator = DesktopPetSkinsFeature.Generator(
            description: "  give it a wizard hat \n", draft: base, isModelSelected: true,
            editingSkinID: dog.id, summary: "dog"
        )
        let store = TestStore(initialState: state) {
            DesktopPetSkinsFeature()
        } withDependencies: {
            $0.desktopPetSkinGeneration.edit = { instruction, base in
                edits.withValue { $0.append(EditCall(instruction: instruction, base: base)) }
                return edited
            }
            $0.desktopPetSkinGeneration.generate = { _ in
                Issue.record("generate must not be called when a draft exists")
                return edited
            }
        }

        await store.send(.generator(.generateTapped)) {
            $0.generator?.isGenerating = true
        }
        await store.receive(\.generator.generated) {
            $0.generator?.isGenerating = false
            $0.generator?.draft = edited
            $0.generator?.summary = "dog\ngive it a wizard hat"
            $0.generator?.description = ""
        }
        await store.finish()

        #expect(edits.value == [EditCall(instruction: "give it a wizard hat", base: base)])
    }

    @Test func failedEditKeepsDescriptionSummaryAndDraft() async {
        let base = DesktopPetSkinDraft(name: "Dog", markup: "<dog>")
        var state = DesktopPetSkinsFeature.State()
        state.generator = DesktopPetSkinsFeature.Generator(
            description: "give it a wizard hat", draft: base, isModelSelected: true,
            editingSkinID: dog.id, summary: "dog"
        )
        let store = TestStore(initialState: state) {
            DesktopPetSkinsFeature()
        } withDependencies: {
            $0.desktopPetSkinGeneration.edit = { _, _ in throw DesktopPetSkinGenerationError.refused("no hats") }
        }

        await store.send(.generator(.generateTapped)) {
            $0.generator?.isGenerating = true
        }
        await store.receive(\.generator.generated) {
            $0.generator?.isGenerating = false
            $0.generator?.errorMessage = "no hats"
        }
        await store.finish()
    }

    @Test(arguments: [("Wizard Dog", "Wizard Dog"), ("", "Dog")])
    func savingEditReplacesSkinInPlace(draftName: String, expectedName: String) async {
        let now = Date(timeIntervalSinceReferenceDate: 5)
        let saved = LockIsolated<[DesktopPetSkin]>([])
        let selected = LockIsolated<[UUID?]>([])
        let notified = LockIsolated(0)
        var state = DesktopPetSkinsFeature.State()
        state.skins = [cat, dog]
        state.selectedID = cat.id
        state.generator = DesktopPetSkinsFeature.Generator(
            draft: DesktopPetSkinDraft(name: draftName, markup: "<wizard-dog>"),
            editingSkinID: dog.id, summary: "dog\ngive it a wizard hat"
        )
        let expected = DesktopPetSkin(
            id: dog.id, name: expectedName, summary: "dog\ngive it a wizard hat", createdAt: dog.createdAt,
            contractVersion: DesktopPetSkinContract.version, markup: "<wizard-dog>"
        )
        let cat = self.cat
        let store = TestStore(initialState: state) {
            DesktopPetSkinsFeature()
        } withDependencies: {
            $0.uuid = .constant(UUID(0))
            $0.date.now = now
            $0.desktopPetSkinLibrary.save = { skin in
                saved.withValue { $0.append(skin) }
                return [cat, skin]
            }
            $0.desktopPetSkinLibrary.select = { id in selected.withValue { $0.append(id) } }
            $0.desktopPetSkinNotifier = { notified.withValue { $0 += 1 } }
        }

        await store.send(.generator(.saveTapped)) {
            $0.generator?.isGenerating = true
        }
        await store.receive(\.saved) {
            $0.skins = [cat, expected]
            $0.selectedID = expected.id
            $0.generator = nil
        }
        await store.finish()

        #expect(saved.value == [expected])
        #expect(selected.value == [dog.id])
        #expect(notified.value == 1)
    }

    @Test func savingEditOfDeletedSkinSavesItAsNew() async {
        let id = UUID(0)
        let now = Date(timeIntervalSinceReferenceDate: 5)
        let saved = LockIsolated<[DesktopPetSkin]>([])
        var state = DesktopPetSkinsFeature.State()
        state.skins = [cat]
        state.generator = DesktopPetSkinsFeature.Generator(
            draft: DesktopPetSkinDraft(name: "Wizard Dog", markup: "<wizard-dog>"),
            editingSkinID: dog.id, summary: "dog\ngive it a wizard hat"
        )
        let expected = DesktopPetSkin(
            id: id, name: "Wizard Dog", summary: "dog\ngive it a wizard hat", createdAt: now,
            contractVersion: DesktopPetSkinContract.version, markup: "<wizard-dog>"
        )
        let cat = self.cat
        let store = TestStore(initialState: state) {
            DesktopPetSkinsFeature()
        } withDependencies: {
            $0.uuid = .constant(id)
            $0.date.now = now
            $0.desktopPetSkinLibrary.save = { skin in
                saved.withValue { $0.append(skin) }
                return [cat, skin]
            }
            $0.desktopPetSkinLibrary.select = { _ in }
            $0.desktopPetSkinNotifier = {}
        }

        await store.send(.generator(.saveTapped)) {
            $0.generator?.isGenerating = true
        }
        await store.receive(\.saved) {
            $0.skins = [cat, expected]
            $0.selectedID = id
            $0.generator = nil
        }
        await store.finish()

        #expect(saved.value == [expected])
    }
}

private struct EditCall: Equatable, Sendable {
    let instruction: String
    let base: DesktopPetSkinDraft
}

private func makeSkin(id: UUID, name: String) -> DesktopPetSkin {
    DesktopPetSkin(
        id: id, name: name, summary: name.lowercased(), createdAt: Date(timeIntervalSinceReferenceDate: 0),
        contractVersion: DesktopPetSkinContract.version, markup: "<div id=\"pet\"></div>"
    )
}
