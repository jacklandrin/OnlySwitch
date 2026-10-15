import ComposableArchitecture
import Foundation
import OnlyAgent
import Extensions

@Reducer
public struct AphroditeReducer {
    @ObservableState
    public struct State: Equatable {
        public enum StorageState: Equatable { case loading, ready, failed }
        public var prompt = ""
        public var apps: IdentifiedArrayOf<AphroditeApp> = []
        public var selection: AphroditeModelSelection?
        public var models: [ModelProvider: [String]] = [:]
        public var modelLoadErrors: [ModelProvider: UserError] = [:]
        public var selectedAppID: UUID?
        public var editingAppID: UUID?
        public var editPrompt = ""
        public var isEditing = false
        public var isGenerating = false
        public var storageState: StorageState = .loading
        public var error: UserError?

        public init(prompt: String = "", apps: IdentifiedArrayOf<AphroditeApp> = [], selection: AphroditeModelSelection? = nil, storageState: StorageState = .loading) {
            self.prompt = prompt; self.apps = apps; self.selection = selection; self.storageState = storageState
        }
    }

    public enum UserError: String, Equatable, Sendable {
        case storageLoadFailed = "Aphrodite could not load your saved apps."
        case saveFailed = "Aphrodite could not save your changes."
        case generationFailed = "Aphrodite could not generate this app."
        case modelLoadFailed = "Models could not be loaded for this provider."
    }

    @CasePathable
    public enum Action {
        case task
        case reloadLibrary
        case libraryLoaded(TaskResult<AphroditeLibrary>)
        case libraryReloaded(TaskResult<AphroditeLibrary>)
        case modelsLoaded(ModelProvider, TaskResult<[String]>)
        case loadModels(ModelProvider)
        case promptChanged(String)
        case providerSelected(ModelProvider)
        case modelSelected(String)
        case generateTapped
        case generationFinished(TaskResult<AphroditeLibrary>)
        case generationFailed
        case cancelGenerationTapped
        case selectApp(UUID?)
        case editTapped(UUID)
        case editPromptChanged(String)
        case sendEditTapped
        case editFinished(TaskResult<AphroditeLibrary>)
        case editGenerationFailed
        case closeEditorTapped
        case editorDisappeared
        case cancelEditTapped
        case deleteTapped(UUID)
        case deletionFinished(TaskResult<AphroditeLibrary>)
        case selectionUpdated(TaskResult<AphroditeLibrary>)
    }

    @Dependency(\.aphroditePersistence) var persistence
    @Dependency(\.modelProviderService) var modelService
    @Dependency(\.uuid) var uuid
    @Dependency(\.date) var date
    private enum CancelID { case generation, edit, selectionUpdate }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { [persistence, modelService] state, action in
            switch action {
            case .task:
                return .run { send in
                    do { await send(.libraryLoaded(.success(try await persistence.load()))) }
                    catch { await send(.libraryLoaded(.failure(error as? AphroditePersistenceClient.Error ?? .loadFailed))) }
                }
            case .reloadLibrary:
                return .run { send in
                    do { await send(.libraryReloaded(.success(try await persistence.load()))) }
                    catch { await send(.libraryReloaded(.failure(error))) }
                }
            case let .libraryReloaded(.success(library)):
                state.apps = IdentifiedArray(uniqueElements: library.apps)
                state.selection = library.selection ?? state.selection
                state.storageState = .ready
                state.error = nil
                if state.selectedAppID.map({ id in !library.apps.contains(where: { $0.id == id }) }) == true {
                    state.selectedAppID = nil
                }
                return .merge(ModelProvider.allCases.compactMap { provider in
                    guard state.models[provider] == nil else { return nil }
                    return .send(.loadModels(provider))
                })
            case .libraryReloaded(.failure):
                state.storageState = .failed; state.error = .storageLoadFailed; return .none
            case let .libraryLoaded(.success(library)):
                state.apps = IdentifiedArray(uniqueElements: library.apps)
                if let selection = library.selection { state.selection = selection }
                state.storageState = .ready
                return .merge(ModelProvider.allCases.map { provider in
                    .run { send in
                        do { await send(.modelsLoaded(provider, .success(try await modelService.models(provider).map(\.model)))) }
                        catch { await send(.modelsLoaded(provider, .failure(AphroditeModelLoadError.failed))) }
                    }
                })
            case .libraryLoaded(.failure):
                state.storageState = .failed; state.error = .storageLoadFailed; return .none
            case let .modelsLoaded(provider, .success(models)):
                state.models[provider] = models
                state.modelLoadErrors[provider] = nil
                guard state.storageState == .ready, let first = models.first else { return .none }
                if state.selection == nil {
                    let selection = AphroditeModelSelection(provider: provider, model: first)
                    state.selection = selection
                    return Self.updateSelection(selection, persistence: persistence)
                }
                if let selection = state.selection,
                   selection.provider == provider,
                   !models.contains(selection.model) {
                    let correctedSelection = AphroditeModelSelection(provider: provider, model: first)
                    state.selection = correctedSelection
                    return Self.updateSelection(correctedSelection, persistence: persistence)
                }
                return .none
            case let .modelsLoaded(provider, .failure):
                state.modelLoadErrors[provider] = .modelLoadFailed; return .none
            case let .loadModels(provider):
                state.modelLoadErrors[provider] = nil
                return .run { send in
                    do { await send(.modelsLoaded(provider, .success(try await modelService.models(provider).map(\.model)))) }
                    catch { await send(.modelsLoaded(provider, .failure(error))) }
                }
            case let .promptChanged(prompt): state.prompt = prompt; return .none
            case let .providerSelected(provider):
                let model = state.models[provider]?.first ?? ""
                let selection = AphroditeModelSelection(provider: provider, model: model)
                state.selection = selection
                guard state.storageState == .ready else { return .none }
                guard !model.isEmpty else {
                    return state.models[provider] == nil ? .send(.loadModels(provider)) : .none
                }
                return Self.updateSelection(selection, persistence: persistence)
            case let .modelSelected(model):
                guard var selection = state.selection else { return .none }
                selection.model = model; state.selection = selection
                guard state.storageState == .ready else { return .none }
                return Self.updateSelection(selection, persistence: persistence)
            case .generateTapped:
                guard state.storageState == .ready, !state.isGenerating, !state.isEditing,
                      let selection = state.selection, !selection.model.isEmpty,
                      state.models[selection.provider]?.contains(selection.model) == true,
                      !state.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .none }
                state.isGenerating = true; state.error = nil
                let prompt = state.prompt, id = uuid(), turnID = uuid(), now = date.now
                return .run { send in
                    do {
                        let response = try await modelService.generateApp(.init(
                            provider: selection.provider, model: selection.model, purpose: .aphrodite,
                            systemInstructions: AphroditePrompt.systemInstructions,
                            prompt: prompt, maximumOutputTokens: 8_192, conversationID: id
                        ))
                        try Task.checkCancellation()
                        let html = try AphroditeHTMLExtractor.extract(response)
                        let iconSVG = AphroditeIconExtractor.extractValidatedSVG(from: html)
                        let app = AphroditeApp(id: id, title: AphroditePrompt.title(in: html), html: html, iconSVG: iconSVG, createdAt: now, updatedAt: now, conversationID: id, conversation: [.init(id: turnID, prompt: prompt, createdAt: now)])
                        let library = try await persistence.insert(app, selection)
                        await send(.generationFinished(.success(library)))
                    } catch is CancellationError { return }
                    catch let error as AphroditePersistenceClient.Error { await send(.generationFinished(.failure(error))) }
                    catch { await send(.generationFailed) }
                }.cancellable(id: CancelID.generation, cancelInFlight: true)
            case let .generationFinished(.success(library)):
                state.isGenerating = false; state.apps = IdentifiedArray(uniqueElements: library.apps); return .none
            case .generationFinished(.failure):
                state.isGenerating = false; state.error = .saveFailed; return .none
            case .generationFailed:
                state.isGenerating = false; state.error = .generationFailed; return .none
            case .cancelGenerationTapped:
                state.isGenerating = false; return .cancel(id: CancelID.generation)
            case let .selectApp(id): state.selectedAppID = id; return .none
            case let .editTapped(id):
                guard !state.isEditing, state.apps[id: id] != nil else { return .none }
                if state.editingAppID != id { state.editPrompt = "" }
                state.editingAppID = id; state.error = nil; return .none
            case let .editPromptChanged(prompt): state.editPrompt = prompt; return .none
            case .sendEditTapped:
                guard state.storageState == .ready, !state.isEditing, !state.isGenerating,
                      let id = state.editingAppID, let app = state.apps[id: id],
                      let selection = state.selection, state.models[selection.provider]?.contains(selection.model) == true else { return .none }
                let prompt = state.editPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !prompt.isEmpty else { return .none }
                state.isEditing = true; state.error = nil
                let turnID = uuid(), now = date.now
                return .run { send in
                    do {
                        let response = try await modelService.generateApp(.init(
                            provider: selection.provider, model: selection.model, purpose: .aphrodite,
                            systemInstructions: AphroditePrompt.editInstructions,
                            prompt: AphroditePrompt.editPrompt(app: app, newPrompt: prompt), maximumOutputTokens: 8_192,
                            conversationID: app.conversationID
                        ))
                        try Task.checkCancellation()
                        let html = try AphroditeHTMLExtractor.extract(response)
                        let updated = AphroditeApp(
                            id: app.id, title: AphroditePrompt.title(in: html), html: html,
                            iconSVG: AphroditeIconExtractor.extractValidatedSVG(from: html) ?? app.iconSVG,
                            createdAt: app.createdAt, updatedAt: now, conversationID: app.conversationID,
                            conversation: app.conversation + [.init(id: turnID, prompt: prompt, createdAt: now)]
                        )
                        let library = try await persistence.update(updated, app)
                        try Task.checkCancellation()
                        await send(.editFinished(.success(library)))
                    } catch is CancellationError { return }
                    catch let error as AphroditePersistenceClient.Error { await send(.editFinished(.failure(error))) }
                    catch { await send(.editGenerationFailed) }
                }.cancellable(id: CancelID.edit, cancelInFlight: true)
            case let .editFinished(.success(library)):
                state.isEditing = false; state.apps = IdentifiedArray(uniqueElements: library.apps); state.editPrompt = ""; return .none
            case .editFinished(.failure): state.isEditing = false; state.error = .saveFailed; return .none
            case .editGenerationFailed: state.isEditing = false; state.error = .generationFailed; return .none
            case .closeEditorTapped:
                state.editingAppID = nil; state.editPrompt = ""; state.isEditing = false; return .cancel(id: CancelID.edit)
            case .editorDisappeared:
                state.isEditing = false; return .cancel(id: CancelID.edit)
            case .cancelEditTapped:
                state.isEditing = false; return .cancel(id: CancelID.edit)
            case let .deleteTapped(id):
                guard state.storageState == .ready else { return .none }
                let cancelsCurrentEdit = state.editingAppID == id
                if cancelsCurrentEdit { state.isEditing = false }
                let deletion: Effect<Action> = .run { send in
                    do { await send(.deletionFinished(.success(try await persistence.delete(id)))) }
                    catch { await send(.deletionFinished(.failure(error as? AphroditePersistenceClient.Error ?? .writeFailed))) }
                }
                return cancelsCurrentEdit ? .merge(.cancel(id: CancelID.edit), deletion) : deletion
            case let .deletionFinished(.success(library)):
                state.apps = IdentifiedArray(uniqueElements: library.apps)
                if state.selectedAppID.map({ id in !library.apps.contains(where: { $0.id == id }) }) == true { state.selectedAppID = nil }
                if state.editingAppID.map({ id in !library.apps.contains(where: { $0.id == id }) }) == true {
                    state.editingAppID = nil
                    state.editPrompt = ""
                    state.isEditing = false
                }
                return .none
            case .deletionFinished(.failure): state.error = .saveFailed; return .none
            case let .selectionUpdated(.success(library)):
                state.apps = IdentifiedArray(uniqueElements: library.apps); state.selection = library.selection; return .none
            case .selectionUpdated(.failure):
                state.error = .saveFailed; return .none
            }
        }
    }

    private static func updateSelection(_ selection: AphroditeModelSelection, persistence: AphroditePersistenceClient) -> Effect<Action> {
        return .run { send in
            do { await send(.selectionUpdated(.success(try await persistence.updateSelection(selection)))) }
            catch is CancellationError { return }
            catch { await send(.selectionUpdated(.failure(error))) }
        }.cancellable(id: CancelID.selectionUpdate, cancelInFlight: true)
    }
}

private enum AphroditeModelLoadError: Error { case failed }

private enum AphroditePrompt {
    static let systemInstructions = """
    Create one complete, self-contained HTML document for a small app. Return HTML only with a concise title element. Put all CSS and JavaScript inline. Do not use URLs, network APIs, external resources, file APIs, forms, or navigation. Keep state in memory; do not use localStorage, sessionStorage, IndexedDB, or cookies. Include responsive layouts and keyboard and touch controls when appropriate.
    Also design a simple static icon and include exactly one optional <template id="aphrodite-app-icon"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">…</svg></template> inside the body whenever you can. Use only svg, g, defs, linearGradient, radialGradient, stop, path, rect, circle, ellipse, line, polyline, and polygon; use numeric geometry, #RRGGBB colors, and local url(#gradientID) paint references. Do not use styles, text, images, hrefs, URLs, scripts, animation, filters, or foreign objects. Omit the template only if you cannot generate an icon.
    """
    static let editInstructions = systemInstructions + "\nUpdate the supplied current app according to the newest request. Return the complete replacement HTML document only."
    static func editPrompt(app: AphroditeApp, newPrompt: String) -> String {
        let history = app.conversation.suffix(8).map { "- \($0.prompt.prefix(500))" }.joined(separator: "\n")
        return """
        Current app HTML:
        \(app.html)

        Recent completed requests:
        \(history)

        New request:
        \(newPrompt)
        """
    }
    static func title(in html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<title[^>]*>(.*?)</title>"#),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return "Untitled App".localized() }
        let value = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Untitled App".localized() : String(value.prefix(80))
    }
}
