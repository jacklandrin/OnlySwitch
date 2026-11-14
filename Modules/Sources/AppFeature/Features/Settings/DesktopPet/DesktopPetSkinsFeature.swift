import ComposableArchitecture
import DesktopPet
import DesktopPetSkinKit
import Extensions
import Foundation
import OnlyAgent
import OSLog

/// The custom pet library, the selection between built-in and custom pets, and the AI generation sheet.
@Reducer
struct DesktopPetSkinsFeature {
    @ObservableState
    struct State: Equatable {
        var skins: [DesktopPetSkin] = []
        var selectedID: UUID?
        var generator: Generator?
    }

    @ObservableState
    struct Generator: Equatable {
        var description = ""
        var isGenerating = false
        var draft: DesktopPetSkinDraft?
        var errorMessage: String?
        var previewAnimation: DesktopPetAnimation = .idle
        var isModelSelected = false
    }

    @CasePathable
    enum GeneratorAction: BindableAction {
        case binding(BindingAction<Generator>)
        case generateTapped
        case generated(Result<DesktopPetSkinDraft, DesktopPetSkinGenerationError>)
        case saveTapped
        case cancelTapped
    }

    enum Action {
        case task
        case loaded([DesktopPetSkin], UUID?)
        case selected(UUID?)
        case deleteTapped(UUID)
        case createTapped
        case generator(GeneratorAction)
        case saved([DesktopPetSkin], UUID)
        case saveFailed(String)
    }

    enum CancelID { case generation }

    @Dependency(\.desktopPetSkinLibrary) var library
    @Dependency(\.desktopPetSkinGeneration) var generation
    @Dependency(\.desktopPetSkinNotifier) var notify
    @Dependency(\.uuid) var uuid
    @Dependency(\.date.now) var now

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return .run { [library] send in
                    await send(.loaded(await library.load(), library.selectedID()))
                }

            case let .loaded(skins, id):
                state.skins = skins
                state.selectedID = id
                return .none

            case let .selected(id):
                state.selectedID = id
                return .run { [library, notify] _ in
                    library.select(id)
                    notify()
                }

            case let .deleteTapped(id):
                return .run { [library, notify] send in
                    do {
                        let remaining = try await library.delete(id)
                        await send(.loaded(remaining, library.selectedID()))
                        notify()
                    } catch {
                        Logger.settings.error("Deleting a desktop pet skin failed")
                    }
                }

            case .createTapped:
                state.generator = Generator(isModelSelected: generation.isModelSelected())
                return .none

            case let .generator(action):
                return reduceGenerator(&state, action)

            case let .saved(skins, id):
                state.skins = skins
                state.selectedID = id
                state.generator = nil
                return .none

            case let .saveFailed(message):
                state.generator?.isGenerating = false
                state.generator?.errorMessage = message
                return .none
            }
        }
        .ifLet(\.generator, action: \.generator) {
            BindingReducer()
        }
    }

    private func reduceGenerator(_ state: inout State, _ action: GeneratorAction) -> Effect<Action> {
        guard var generator = state.generator else { return .none }
        defer { if state.generator != nil { state.generator = generator } }

        switch action {
        case .binding:
            return .none

        case .generateTapped:
            let description = generator.description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !description.isEmpty else { return .none }
            generator.isGenerating = true
            generator.errorMessage = nil
            return .run { [generation] send in
                do {
                    await send(.generator(.generated(.success(try await generation.generate(description)))))
                } catch let error as DesktopPetSkinGenerationError {
                    await send(.generator(.generated(.failure(error))))
                } catch is CancellationError {
                    return
                } catch {
                    // Network and provider errors: show the generic message. Never log the error, it may echo the request.
                    await send(.generator(.generated(.failure(.noMarkup))))
                }
            }
            .cancellable(id: CancelID.generation, cancelInFlight: true)

        case let .generated(.success(draft)):
            generator.isGenerating = false
            generator.draft = draft
            return .none

        case let .generated(.failure(error)):
            generator.isGenerating = false
            switch error {
            case .noModelSelected: generator.errorMessage = "Desktop Pet No Model".localized()
            case let .refused(reason): generator.errorMessage = reason
            case .invalid, .noMarkup: generator.errorMessage = "Desktop Pet Generation Failed".localized()
            }
            return .none

        case .saveTapped:
            guard let draft = generator.draft else { return .none }
            generator.isGenerating = true
            let skin = DesktopPetSkin(
                id: uuid(),
                name: draft.name.isEmpty ? String(generator.description.prefix(20)) : draft.name,
                summary: generator.description,
                createdAt: now,
                contractVersion: DesktopPetSkinContract.version,
                markup: draft.markup
            )
            return .run { [library, notify] send in
                do {
                    let skins = try await library.save(skin)
                    library.select(skin.id)
                    notify()
                    await send(.saved(skins, skin.id))
                } catch DesktopPetSkinLibraryError.full {
                    await send(.saveFailed("Desktop Pet Skins Full".localized()))
                } catch {
                    Logger.settings.error("Saving a desktop pet skin failed")
                    await send(.saveFailed("Desktop Pet Generation Failed".localized()))
                }
            }

        case .cancelTapped:
            state.generator = nil
            return .cancel(id: CancelID.generation)
        }
    }
}
