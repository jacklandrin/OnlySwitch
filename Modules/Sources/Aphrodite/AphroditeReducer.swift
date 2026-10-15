import ComposableArchitecture
import Foundation
import OnlyAgent
import Extensions

public struct AphroditeEditOperation: Equatable, Sendable {
    public let taskID: UUID
    public let appID: UUID

    public init(taskID: UUID, appID: UUID) {
        self.taskID = taskID
        self.appID = appID
    }
}

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
        public var activeEdit: AphroditeEditOperation?
        public var activeGenerationID: UUID?
        public var isEditing: Bool { activeEdit != nil }
        public var isGenerating: Bool { activeGenerationID != nil }
        public var storageState: StorageState = .loading
        public var error: UserError?
        public var isImporting = false
        public var importError: UserError?
        public var hasStartedInitialLoad = false

        public init(prompt: String = "", apps: IdentifiedArrayOf<AphroditeApp> = [], selection: AphroditeModelSelection? = nil, storageState: StorageState = .loading) {
            self.prompt = prompt; self.apps = apps; self.selection = selection; self.storageState = storageState
        }
    }

    public enum UserError: String, Equatable, Sendable {
        case storageLoadFailed = "Aphrodite could not load your saved apps."
        case saveFailed = "Aphrodite could not save your changes."
        case generationFailed = "Aphrodite could not generate this app."
        case modelLoadFailed = "Models could not be loaded for this provider."
        case importFailed = "This mini app could not be imported."
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
        case generationFinished(UUID, TaskResult<AphroditeLibrary>)
        case generationFailed(UUID)
        case cancelGenerationTapped
        case selectApp(UUID?)
        case editTapped(UUID)
        case editPromptChanged(String)
        case sendEditTapped
        case editFinished(AphroditeEditOperation, TaskResult<AphroditeLibrary>)
        case editGenerationFailed(AphroditeEditOperation)
        case closeEditorTapped
        case editorDisappeared
        case cancelEditTapped
        case deleteTapped(UUID)
        case deletionFinished(UUID, TaskResult<AphroditeLibrary>)
        case importTapped
        case importPickerDismissed
        case importErrorDismissed
        case importDocument(Data)
        case importFinished(TaskResult<AphroditeLibrary>)
        case selectionUpdated(TaskResult<AphroditeLibrary>)
    }

    @Dependency(\.aphroditePersistence) var persistence
    @Dependency(\.aphroditeWebStorage) var webStorage
    @Dependency(\.aphroditeLocalNotification) var notification
    @Dependency(\.modelProviderService) var modelService
    @Dependency(\.uuid) var uuid
    @Dependency(\.date) var date
    private enum CancelID { case generation, edit, selectionUpdate }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { [persistence, modelService, webStorage, notification] state, action in
            switch action {
            case .task:
                guard state.storageState == .loading, !state.hasStartedInitialLoad else { return .none }
                state.hasStartedInitialLoad = true
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
                if state.editingAppID.map({ id in !library.apps.contains(where: { $0.id == id }) }) == true {
                    state.editingAppID = nil
                    state.editPrompt = ""
                }
                var effects: [Effect<Action>] = ModelProvider.allCases.compactMap { provider in
                    guard state.models[provider] == nil else { return nil }
                    return .send(.loadModels(provider))
                }
                if let activeEdit = state.activeEdit,
                   !library.apps.contains(where: { $0.id == activeEdit.appID }) {
                    state.activeEdit = nil
                    effects.append(.cancel(id: CancelID.edit))
                }
                return .merge(effects)
            case .libraryReloaded(.failure):
                state.storageState = .failed; state.error = .storageLoadFailed; return .none
            case let .libraryLoaded(.success(library)):
                guard state.storageState == .loading else {
                    state.hasStartedInitialLoad = false
                    return .none
                }
                state.hasStartedInitialLoad = false
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
                guard state.storageState == .loading else {
                    state.hasStartedInitialLoad = false
                    return .none
                }
                state.hasStartedInitialLoad = false; state.storageState = .failed; state.error = .storageLoadFailed; return .none
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
                let taskID = uuid()
                state.activeGenerationID = taskID; state.error = nil
                let prompt = state.prompt, id = uuid(), turnID = uuid(), now = date.now
                return .run { send in
                    async let isAuthorized = try? notification.requestAuthorization()
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
                        try Task.checkCancellation()
                        if await isAuthorized == true {
                            try Task.checkCancellation()
                            try? await notification.deliver(Self.completionNotification(taskID: taskID, title: app.title))
                        }
                        await send(.generationFinished(taskID, .success(library)))
                    } catch is CancellationError { return }
                    catch let error as AphroditePersistenceClient.Error { await send(.generationFinished(taskID, .failure(error))) }
                    catch { await send(.generationFailed(taskID)) }
                }.cancellable(id: CancelID.generation, cancelInFlight: true)
            case let .generationFinished(taskID, .success(library)) where state.activeGenerationID == taskID:
                state.activeGenerationID = nil; state.apps = IdentifiedArray(uniqueElements: library.apps); return .none
            case let .generationFinished(taskID, .failure) where state.activeGenerationID == taskID:
                state.activeGenerationID = nil; state.error = .saveFailed; return .none
            case let .generationFailed(taskID) where state.activeGenerationID == taskID:
                state.activeGenerationID = nil; state.error = .generationFailed; return .none
            case .generationFinished, .generationFailed:
                return .none
            case .cancelGenerationTapped:
                state.activeGenerationID = nil; return .cancel(id: CancelID.generation)
            case let .selectApp(id): state.selectedAppID = id; return .none
            case let .editTapped(id):
                guard state.apps[id: id] != nil,
                      state.activeEdit == nil || state.activeEdit?.appID == id else { return .none }
                if state.editingAppID != id, state.activeEdit?.appID != id { state.editPrompt = "" }
                state.editingAppID = id; state.error = nil; return .none
            case let .editPromptChanged(prompt): state.editPrompt = prompt; return .none
            case .sendEditTapped:
                guard state.storageState == .ready, !state.isEditing, !state.isGenerating,
                      let id = state.editingAppID, let app = state.apps[id: id],
                      let selection = state.selection, state.models[selection.provider]?.contains(selection.model) == true else { return .none }
                let prompt = state.editPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !prompt.isEmpty else { return .none }
                let operation = AphroditeEditOperation(taskID: uuid(), appID: id)
                state.activeEdit = operation; state.error = nil
                let turnID = uuid(), now = date.now
                return .run { send in
                    async let isAuthorized = try? notification.requestAuthorization()
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
                        if await isAuthorized == true {
                            try Task.checkCancellation()
                            try? await notification.deliver(Self.completionNotification(taskID: operation.taskID, title: updated.title))
                        }
                        await send(.editFinished(operation, .success(library)))
                    } catch is CancellationError { return }
                    catch let error as AphroditePersistenceClient.Error { await send(.editFinished(operation, .failure(error))) }
                    catch { await send(.editGenerationFailed(operation)) }
                }.cancellable(id: CancelID.edit, cancelInFlight: true)
            case let .editFinished(operation, .success(library)) where state.activeEdit?.taskID == operation.taskID:
                state.activeEdit = nil; state.apps = IdentifiedArray(uniqueElements: library.apps); state.editPrompt = ""; return .none
            case let .editFinished(operation, .failure) where state.activeEdit?.taskID == operation.taskID:
                state.activeEdit = nil; state.error = .saveFailed; return .none
            case let .editGenerationFailed(operation) where state.activeEdit?.taskID == operation.taskID:
                state.activeEdit = nil; state.error = .generationFailed; return .none
            case .editFinished, .editGenerationFailed:
                return .none
            case .closeEditorTapped:
                state.editingAppID = nil; return .none
            case .editorDisappeared:
                return .none
            case .cancelEditTapped:
                state.activeEdit = nil; return .cancel(id: CancelID.edit)
            case let .deleteTapped(id):
                guard state.storageState == .ready else { return .none }
                let cancelsCurrentEdit = state.activeEdit?.appID == id
                if cancelsCurrentEdit { state.activeEdit = nil }
                let deletion: Effect<Action> = .run { send in
                    do { await send(.deletionFinished(id, .success(try await persistence.delete(id)))) }
                    catch { await send(.deletionFinished(id, .failure(error as? AphroditePersistenceClient.Error ?? .writeFailed))) }
                }
                return cancelsCurrentEdit ? .merge(.cancel(id: CancelID.edit), deletion) : deletion
            case let .deletionFinished(id, .success(library)):
                state.apps = IdentifiedArray(uniqueElements: library.apps)
                if state.selectedAppID.map({ id in !library.apps.contains(where: { $0.id == id }) }) == true { state.selectedAppID = nil }
                if state.editingAppID.map({ id in !library.apps.contains(where: { $0.id == id }) }) == true {
                    state.editingAppID = nil
                    state.editPrompt = ""
                }
                let origin = AphroditeAppOrigin(appID: id)
                return .run { _ in await webStorage.removeData(origin) }
            case .deletionFinished(_, .failure): state.error = .saveFailed; return .none
            case .importTapped:
                state.isImporting = true
                state.importError = nil
                return .none
            case .importPickerDismissed:
                state.isImporting = false
                return .none
            case .importErrorDismissed:
                state.importError = nil
                return .none
            case let .importDocument(data):
                state.isImporting = false
                guard state.storageState == .ready else { return .none }
                state.error = nil
                let id = uuid(), now = date.now
                return .run { send in
                    do {
                        let document = try AphroditeShareDocument.decode(data)
                        let app = AphroditeApp(
                            id: id,
                            title: document.title,
                            html: document.html,
                            iconSVG: document.iconSVG,
                            createdAt: now,
                            updatedAt: now,
                            conversationID: id,
                            conversation: []
                        )
                        await send(.importFinished(.success(try await persistence.insertImported(app))))
                    } catch {
                        await send(.importFinished(.failure(error)))
                    }
                }
            case let .importFinished(.success(library)):
                state.apps = IdentifiedArray(uniqueElements: library.apps)
                state.importError = nil
                return .none
            case .importFinished(.failure):
                state.importError = .importFailed
                return .none
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

    private static func completionNotification(taskID: UUID, title: String) -> AphroditeCompletionNotification {
        AphroditeCompletionNotification(
            identifier: "aphrodite.\(taskID.uuidString)",
            title: "Aphrodite finished your mini app".localized(),
            body: String(format: "“%@” is ready to use.".localized(), title)
        )
    }
}

private enum AphroditeModelLoadError: Error { case failed }

private enum AphroditePrompt {
    static let systemInstructions = """
    Create one complete, self-contained HTML document for a small app. Return HTML only with a concise title element. Put all CSS and JavaScript inline. Use localStorage only for durable user state that should survive closing and reopening the app. Do not use cookies, sessionStorage, IndexedDB, Cache Storage, network APIs, external resources, file APIs, forms, navigation, or popups. Use CSS custom properties for adaptive colors, declare color-scheme: light dark, and include a complete @media (prefers-color-scheme: dark) override. Include responsive layouts, semantic accessible controls, visible keyboard focus, and keyboard and touch controls when appropriate. Use only static inline icons.
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
