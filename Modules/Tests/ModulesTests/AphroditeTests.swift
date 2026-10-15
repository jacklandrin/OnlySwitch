import Aphrodite
import ComposableArchitecture
import Foundation
import OnlyAgent
import Testing

#if os(macOS)
import AppKit
#endif

struct AphroditeHTMLExtractorTests {
    @Test func extractsOnlyACompleteFencedHTMLDocument() throws {
        let response = """
        Here is your mini app:
        ```html
        <!doctype html><html><head><title>Counter</title></head><body><button>0</button></body></html>
        ```
        """

        #expect(
            try AphroditeHTMLExtractor.extract(response) == "<!doctype html><html><head><title>Counter</title></head><body><button>0</button></body></html>"
        )
    }

    @Test func rejectsProseFragmentsAndOversizedDocuments() {
        #expect(throws: AphroditeHTMLExtractor.Error.missingCompleteDocument) {
            try AphroditeHTMLExtractor.extract("<button>Not a document</button>")
        }
        #expect(throws: AphroditeHTMLExtractor.Error.documentTooLarge) {
            try AphroditeHTMLExtractor.extract(String(repeating: "x", count: AphroditeHTMLExtractor.maximumDocumentBytes + 1))
        }
    }
}

struct AphroditePersistenceTests {
    @Test func legacyAppsDecodeWithAnEditableEmptyConversation() throws {
        let legacy = LegacyAphroditeApp(
            id: UUID(), title: "Legacy", html: completeHTML,
            createdAt: .distantPast, updatedAt: .distantPast
        )

        let decoded = try JSONDecoder().decode(AphroditeApp.self, from: JSONEncoder().encode(legacy))

        #expect(decoded.conversation.isEmpty)
        #expect(decoded.conversationID == legacy.id)
        #expect(try JSONDecoder().decode(AphroditeApp.self, from: JSONEncoder().encode(legacy)).conversationID == decoded.conversationID)
    }

    @Test func updateReplacesOnlyTheExpectedAppAndKeepsTheLibrarySelection() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = AphroditeApp(id: UUID(), title: "Counter", html: completeHTML, createdAt: .distantPast, updatedAt: .distantPast)
        let sibling = AphroditeApp(id: UUID(), title: "Timer", html: completeHTML, createdAt: .distantPast, updatedAt: .distantPast)
        let selection = AphroditeModelSelection(provider: .gemini, model: "gemini-3.8-flash")
        let updated = AphroditeApp(
            id: original.id, title: "Counter Plus", html: updatedHTML,
            iconSVG: original.iconSVG, createdAt: original.createdAt, updatedAt: .now,
            conversationID: original.conversationID,
            conversation: [.init(id: UUID(), prompt: "Add a reset button", createdAt: .now)]
        )
        let client = AphroditePersistenceClient.fileSystem(directory: directory)
        _ = try await client.replace(.init(apps: [original, sibling], selection: selection))

        let library = try await client.update(updated, original)

        #expect(library.apps == [updated, sibling])
        #expect(library.selection == selection)
    }

    @Test func updateRejectsDeletedAndStaleExpectedAppsWithoutRestoringThem() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = AphroditeApp(id: UUID(), title: "Counter", html: completeHTML, createdAt: .distantPast, updatedAt: .distantPast)
        let revised = AphroditeApp(id: original.id, title: "Newer", html: updatedHTML, createdAt: original.createdAt, updatedAt: .now, conversationID: original.conversationID, conversation: [])
        let client = AphroditePersistenceClient.fileSystem(directory: directory)
        _ = try await client.replace(.init(apps: [original]))
        _ = try await client.update(revised, expected: original)

        await #expect(throws: AphroditePersistenceClient.Error.staleRevision) {
            try await client.update(original, original)
        }
        _ = try await client.delete(original.id)
        await #expect(throws: AphroditePersistenceClient.Error.missingApp) {
            try await client.update(revised, revised)
        }
        #expect(try await client.load().apps.isEmpty)
    }

    @Test func absentStoreLoadsAnEmptyLibrary() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let client = AphroditePersistenceClient.fileSystem(directory: directory)
        #expect(try await client.load() == AphroditeLibrary())
    }

    @Test func roundTripPreservesStableIDsAndIndependentModelSelection() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID(uuidString: "C5D159C4-5299-4DF3-851F-26D2E1C2C0A1")!
        let library = AphroditeLibrary(
            apps: [.init(id: id, title: "Counter", html: completeHTML, createdAt: .distantPast, updatedAt: .distantPast)],
            selection: .init(provider: .gemini, model: "gemini-3.8-flash")
        )
        let client = AphroditePersistenceClient.fileSystem(directory: directory)

        let saved = try await client.replace(library)

        #expect(saved == library)
        #expect(try await client.load() == library)
    }

    @Test func corruptStoreThrowsWithoutReplacingTheOriginalFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "apps.json")
        let corruptData = Data("not json".utf8)
        try corruptData.write(to: fileURL)
        let client = AphroditePersistenceClient.fileSystem(directory: directory)

        await #expect(throws: AphroditePersistenceClient.Error.corruptStore) {
            try await client.load()
        }
        #expect(try Data(contentsOf: fileURL) == corruptData)
    }

    @Test func serializedInsertAndSelectionMutationsKeepBothFeatureStoresChanges() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = AphroditePersistenceClient.fileSystem(directory: directory)
        let selection = AphroditeModelSelection(provider: .openai, model: "gpt-test")
        let first = AphroditeApp(id: UUID(), title: "First", html: completeHTML, createdAt: .distantPast, updatedAt: .distantPast)
        let second = AphroditeApp(id: UUID(), title: "Second", html: completeHTML, createdAt: .distantPast, updatedAt: .distantPast)

        async let firstResult = client.insert(first, selection)
        async let secondResult = client.insert(second, selection)
        async let selectionResult = client.updateSelection(.init(provider: .gemini, model: "gemini-3.8-flash"))
        _ = try await (firstResult, secondResult, selectionResult)

        let library = try await client.load()
        #expect(Set(library.apps.map(\.id)) == Set([first.id, second.id]))
        #expect(library.selection == .init(provider: .gemini, model: "gemini-3.8-flash"))
    }

    @Test func completingAGenerationDoesNotRollBackANewerModelSelection() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = AphroditePersistenceClient.fileSystem(directory: directory)
        let capturedGenerationSelection = AphroditeModelSelection(provider: .gemini, model: "gemini-3.8-flash")
        let newerSelection = AphroditeModelSelection(provider: .claude, model: "claude-opus-5-5")
        let app = AphroditeApp(id: UUID(), title: "Counter", html: completeHTML, createdAt: .distantPast, updatedAt: .distantPast)

        _ = try await client.updateSelection(newerSelection)
        let library = try await client.insert(app, capturedGenerationSelection)

        #expect(library.apps == [app])
        #expect(library.selection == newerSelection)
    }

    @Test func invalidLibrariesAreNotWritten() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = AphroditePersistenceClient.fileSystem(directory: directory)
        let duplicateID = UUID()
        let invalid = AphroditeLibrary(apps: [
            .init(id: duplicateID, title: "One", html: completeHTML, createdAt: .distantPast, updatedAt: .distantPast),
            .init(id: duplicateID, title: "Two", html: completeHTML, createdAt: .distantPast, updatedAt: .distantPast)
        ])

        await #expect(throws: AphroditePersistenceClient.Error.writeFailed) {
            try await client.replace(invalid)
        }
        #expect(try await client.load() == AphroditeLibrary())
    }
}

struct AphroditeIconTests {
    @Test func extractsAStaticIconFromTheDedicatedBodyTemplate() {
        let html = completeHTML.replacingOccurrences(
            of: "</body>",
            with: "<template id=\"aphrodite-app-icon\">\(validIconSVG)</template></body>"
        )

        #expect(AphroditeIconExtractor.extractValidatedSVG(from: html) == validIconSVG)
    }

    @Test(arguments: [
        "<!DOCTYPE svg><svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\"><rect width=\"64\" height=\"64\"/></svg>",
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\"><script>alert(1)</script></svg>",
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\"><rect width=\"64\" height=\"64\" onclick=\"alert(1)\"/></svg>",
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\"><image href=\"https://example.com/icon.svg\"/></svg>",
        "<svg xmlns=\"https://example.com/svg\" viewBox=\"0 0 64 64\"><rect width=\"64\" height=\"64\"/></svg>",
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 Infinity 64\"><rect width=\"64\" height=\"64\"/></svg>",
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\"><rect width=\"64\" height=\"64\" transform=\"translate(Infinity 0)\"/></svg>",
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\"><rect width=\"not-a-number\" height=\"64\"/></svg>",
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\"><rect width=\"64\" height=\"64\" transform=\"translate(1e999 0)\"/></svg>",
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\"><path d=\"M1e999 0 L0 64\"/></svg>",
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\"><rect width=\"64\" height=\"64\" fill=\"url(https://example.com/paint)\"/></svg>",
        "<?test unsafe?><svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\"><rect width=\"64\" height=\"64\"/></svg>",
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\"><defs><rect width=\"64\" height=\"64\"/></defs></svg>",
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\"></svg>"
    ])
    func rejectsUnsafeOrNonVisibleSVG(_ svg: String) {
        #expect(AphroditeSVGValidator.validated(svg) == nil)
    }

    @Test func acceptsStrictlyLocalGradientPaint() {
        let gradient = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\"><defs><linearGradient id=\"accent\"><stop offset=\"0\" stop-color=\"#6750A4\"/><stop offset=\"100%\" stop-color=\"#FFFFFF\"/></linearGradient></defs><rect width=\"64\" height=\"64\" fill=\"url(#accent)\"/></svg>"
        #expect(AphroditeSVGValidator.validated(gradient) == gradient)
    }

    @Test func rejectsOversizedAndExcessivelyNestedSVG() {
        let oversized = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\"><path d=\"\(String(repeating: "M0 0 ", count: 6_000))\"/></svg>"
        let nested = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\">" + String(repeating: "<g>", count: 65) + "<rect width=\"64\" height=\"64\"/>" + String(repeating: "</g>", count: 65) + "</svg>"

        #expect(AphroditeSVGValidator.validated(oversized) == nil)
        #expect(AphroditeSVGValidator.validated(nested) == nil)
    }

    @Test func ignoresMissingMalformedOrUnsafeTemplatesWithoutAffectingHTML() {
        let malformed = completeHTML.replacingOccurrences(of: "</body>", with: "<template id=\"aphrodite-app-icon\"><svg><script/></svg></template></body>")

        #expect(AphroditeIconExtractor.extractValidatedSVG(from: completeHTML) == nil)
        #expect(AphroditeIconExtractor.extractValidatedSVG(from: malformed) == nil)
        let extractedHTML = try? AphroditeHTMLExtractor.extract(malformed)
        #expect(extractedHTML == malformed)
    }
}

struct AphroditeIconPersistenceTests {
    @Test func validIconRoundTripsWithItsApp() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AphroditeApp(id: UUID(), title: "Counter", html: completeHTML, iconSVG: validIconSVG, createdAt: .distantPast, updatedAt: .distantPast)
        let client = AphroditePersistenceClient.fileSystem(directory: directory)

        _ = try await client.replace(.init(apps: [app]))

        #expect(try await client.load().apps == [app])
    }

    @Test func legacyAppJSONWithoutIconDecodesAsNil() throws {
        let legacy = LegacyAphroditeApp(id: UUID(), title: "Legacy", html: completeHTML, createdAt: .distantPast, updatedAt: .distantPast)
        let decoded = try JSONDecoder().decode(AphroditeApp.self, from: JSONEncoder().encode(legacy))

        #expect(decoded.iconSVG == nil)
    }

    @Test func unsafePersistedIconDecodesAsNil() throws {
        let app = IconBearingAphroditeApp(id: UUID(), title: "Unsafe", html: completeHTML, iconSVG: "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\"><script/></svg>", createdAt: .distantPast, updatedAt: .distantPast)
        let decoded = try JSONDecoder().decode(AphroditeApp.self, from: JSONEncoder().encode(app))

        #expect(decoded.iconSVG == nil)
    }
}

struct AphroditeReducerTests {
    @MainActor
    @Test func generationPersistsAValidatedIconFromTheSameModelResponse() async {
        let id = UUID(uuidString: "C5D159C4-5299-4DF3-851F-26D2E1C2C0A3")!
        let response = completeHTML.replacingOccurrences(of: "</body>", with: "<template id=\"aphrodite-app-icon\">\(validIconSVG)</template></body>")
        let app = AphroditeApp(id: id, title: "Counter", html: response, iconSVG: validIconSVG, createdAt: .distantPast, updatedAt: .distantPast, conversationID: id, conversation: [.init(id: id, prompt: "Build a counter", createdAt: .distantPast)])
        let library = AphroditeLibrary(apps: [app], selection: .init(provider: .openai, model: "gpt-test"))
        let store = TestStore(initialState: AphroditeReducer.State(prompt: "Build a counter", selection: library.selection, storageState: .ready).withModels([.openai: ["gpt-test"]])) { AphroditeReducer() } withDependencies: {
            $0.uuid = .constant(id)
            $0.date.now = .distantPast
            $0.modelProviderService.generateApp = { request in
                #expect(request.systemInstructions.contains("aphrodite-app-icon"))
                return response
            }
            $0.aphroditePersistence.insert = { inserted, _ in
                #expect(inserted == app)
                return library
            }
        }

        await store.send(.generateTapped) { $0.isGenerating = true }
        await store.receive(\.generationFinished) { $0.isGenerating = false; $0.apps = [app] }
        await store.finish()
    }

    @MainActor
    @Test func missingOrUnsafeIconStillPersistsTheGeneratedApp() async {
        let id = UUID(uuidString: "C5D159C4-5299-4DF3-851F-26D2E1C2C0A4")!
        let response = completeHTML.replacingOccurrences(of: "</body>", with: "<template id=\"aphrodite-app-icon\"><svg><script/></svg></template></body>")
        let app = AphroditeApp(id: id, title: "Counter", html: response, iconSVG: nil, createdAt: .distantPast, updatedAt: .distantPast, conversationID: id, conversation: [.init(id: id, prompt: "Build a counter", createdAt: .distantPast)])
        let library = AphroditeLibrary(apps: [app], selection: .init(provider: .openai, model: "gpt-test"))
        let store = TestStore(initialState: AphroditeReducer.State(prompt: "Build a counter", selection: library.selection, storageState: .ready).withModels([.openai: ["gpt-test"]])) { AphroditeReducer() } withDependencies: {
            $0.uuid = .constant(id); $0.date.now = .distantPast
            $0.modelProviderService.generateApp = { _ in response }
            $0.aphroditePersistence.insert = { inserted, _ in
                #expect(inserted == app)
                return library
            }
        }

        await store.send(.generateTapped) { $0.isGenerating = true }
        await store.receive(\.generationFinished) { $0.isGenerating = false; $0.apps = [app] }
        await store.finish()
    }

    @MainActor
    @Test func generatesAndPersistsASelectedProvidersSelfContainedApp() async {
        let id = UUID(uuidString: "C5D159C4-5299-4DF3-851F-26D2E1C2C0A2")!
        let generated = AphroditeApp(id: id, title: "Counter", html: completeHTML, createdAt: .distantPast, updatedAt: .distantPast, conversationID: id, conversation: [.init(id: id, prompt: "Build a counter", createdAt: .distantPast)])
        let expectedLibrary = AphroditeLibrary(
            apps: [generated],
            selection: .init(provider: .gemini, model: "gemini-3.8-flash")
        )
        let store = TestStore(initialState: AphroditeReducer.State(
            prompt: "Build a counter",
            selection: expectedLibrary.selection,
            storageState: .ready
        ).withModels([.gemini: ["gemini-3.8-flash"]])) { AphroditeReducer() } withDependencies: {
            $0.uuid = .constant(id)
            $0.date.now = .distantPast
            $0.modelProviderService.generateApp = { request in
                #expect(request.provider == .gemini)
                #expect(request.model == "gemini-3.8-flash")
                #expect(request.purpose == .aphrodite)
                #expect(request.systemInstructions.contains("self-contained"))
                #expect(request.maximumOutputTokens >= 8_192)
                return completeHTML
            }
            $0.aphroditePersistence.insert = { app, selection in
                #expect(app == generated)
                #expect(selection == expectedLibrary.selection)
                return expectedLibrary
            }
        }

        await store.send(.generateTapped) { $0.isGenerating = true }
        await store.receive(\.generationFinished) {
            $0.isGenerating = false
            $0.apps = [generated]
        }
        await store.finish()
    }

    @MainActor
    @Test func saveFailureLeavesExistingAppsAndSelectionUnchanged() async {
        let existing = AphroditeApp(id: UUID(), title: "Existing", html: completeHTML, createdAt: .distantPast, updatedAt: .distantPast)
        let initial = AphroditeReducer.State(
            prompt: "Build a counter",
            apps: [existing],
            selection: .init(provider: .openai, model: "gpt-test"),
            storageState: .ready
        ).withModels([.openai: ["gpt-test"]])
        let store = TestStore(initialState: initial) { AphroditeReducer() } withDependencies: {
            $0.uuid = .constant(UUID())
            $0.date.now = .distantPast
            $0.modelProviderService.generateApp = { request in
                #expect(request.purpose == .aphrodite)
                #expect(request.systemInstructions.contains("self-contained"))
                #expect(request.maximumOutputTokens >= 8_192)
                return completeHTML
            }
            $0.aphroditePersistence.insert = { _, _ in throw AphroditePersistenceClient.Error.writeFailed }
        }

        await store.send(.generateTapped) { $0.isGenerating = true }
        await store.receive(\.generationFinished) {
            $0.isGenerating = false
            $0.error = .saveFailed
        }
        #expect(store.state.apps == [existing])
        #expect(store.state.selection == .init(provider: .openai, model: "gpt-test"))
        await store.finish()
    }

    @MainActor
    @Test func modelLoadFailuresAreScopedToTheirProvider() async {
        let store = TestStore(initialState: AphroditeReducer.State()) { AphroditeReducer() }

        for provider in ModelProvider.allCases {
            await store.send(.modelsLoaded(provider, .success(["\(provider.rawValue)-model"]))) {
                $0.models[provider] = ["\(provider.rawValue)-model"]
            }
        }
        await store.send(.modelsLoaded(.claude, .failure(AphroditeTestError.failed))) {
            $0.modelLoadErrors[.claude] = .modelLoadFailed
        }
        #expect(store.state.models[.openai] == ["openai-model"])
        #expect(store.state.models[.claude] == ["claude-model"])
        await store.finish()
    }

    @MainActor
    @Test func loadFailureBlocksGenerationAndPersistenceWrites() async {
        let store = TestStore(initialState: AphroditeReducer.State(prompt: "Build a counter")) { AphroditeReducer() } withDependencies: {
            $0.aphroditePersistence.load = { throw AphroditePersistenceClient.Error.corruptStore }
            $0.modelProviderService.generateApp = { _ in Issue.record("Generation must not run after a load failure"); return completeHTML }
            $0.aphroditePersistence.insert = { _, _ in Issue.record("Insert must not run after a load failure"); return AphroditeLibrary() }
        }

        await store.send(.task)
        await store.receive(\.libraryLoaded) {
            $0.storageState = .failed
            $0.error = .storageLoadFailed
        }
        await store.send(.generateTapped)
        await store.finish()
    }

    @MainActor
    @Test func aSuccessfulRetryRestoresWritesAfterALoadFailure() async {
        let library = AphroditeLibrary()
        let initial = AphroditeReducer.State(prompt: "Build a counter").withModels(
            Dictionary(uniqueKeysWithValues: ModelProvider.allCases.map { ($0, []) })
        )
        let store = TestStore(initialState: initial) { AphroditeReducer() } withDependencies: {
            $0.aphroditePersistence.load = { library }
        }

        await store.send(.libraryLoaded(.failure(AphroditePersistenceClient.Error.corruptStore))) {
            $0.storageState = .failed
            $0.error = .storageLoadFailed
        }
        await store.send(.reloadLibrary)
        await store.receive(\.libraryReloaded) {
            $0.storageState = .ready
            $0.error = nil
        }
        await store.finish()
    }

    @MainActor
    @Test func generationWaitsForAValidLoadedModel() async {
        let store = TestStore(initialState: AphroditeReducer.State(
            prompt: "Build a counter",
            selection: .init(provider: .openai, model: "retired-model"),
            storageState: .ready
        ).withModels([.openai: ["current-model"]])) { AphroditeReducer() } withDependencies: {
            $0.modelProviderService.generateApp = { _ in
                Issue.record("Generation must not run with a model absent from the current catalog")
                return completeHTML
            }
        }

        await store.send(.generateTapped)
        await store.finish()
    }

    @MainActor
    @Test func cancelPreventsLateGenerationFromPersistingAnApp() async {
        let continuation = LockIsolated<CheckedContinuation<String, Error>?>(nil)
        let store = TestStore(initialState: AphroditeReducer.State(
            prompt: "Build a counter",
            selection: .init(provider: .openai, model: "gpt-test"),
            storageState: .ready
        ).withModels([.openai: ["gpt-test"]])) { AphroditeReducer() } withDependencies: {
            $0.uuid = .constant(UUID())
            $0.date.now = .distantPast
            $0.modelProviderService.generateApp = { _ in
                try await withCheckedThrowingContinuation { newContinuation in
                    continuation.withValue { $0 = newContinuation }
                }
            }
            $0.aphroditePersistence.insert = { _, _ in Issue.record("Cancelled generation must not insert"); return AphroditeLibrary() }
        }

        await store.send(.generateTapped) { $0.isGenerating = true }
        await store.send(.cancelGenerationTapped) { $0.isGenerating = false }
        continuation.withValue { $0?.resume(returning: completeHTML) }
        await store.finish()
        #expect(store.state.apps.isEmpty)
    }

    @MainActor
    @Test func editingAppSendsBoundedConversationAndAtomicallyUpdatesTheSameRecord() async {
        let appID = UUID(uuidString: "C5D159C4-5299-4DF3-851F-26D2E1C2C211")!
        let conversationID = UUID(uuidString: "C5D159C4-5299-4DF3-851F-26D2E1C2C212")!
        let turnID = UUID(uuidString: "C5D159C4-5299-4DF3-851F-26D2E1C2C213")!
        let editDate = Date(timeIntervalSince1970: 1_000)
        let history = (0..<10).map { AphroditeConversationTurn(id: UUID(), prompt: "History \($0)", createdAt: .distantPast) }
        let original = AphroditeApp(id: appID, title: "Counter", html: completeHTML, iconSVG: validIconSVG, createdAt: .distantPast, updatedAt: .distantPast, conversationID: conversationID, conversation: history)
        let generated = updatedHTML
        let expected = AphroditeApp(
            id: appID, title: "Counter Plus", html: generated, iconSVG: validIconSVG,
            createdAt: .distantPast, updatedAt: editDate, conversationID: conversationID,
            conversation: history + [.init(id: turnID, prompt: "Add a reset button", createdAt: editDate)]
        )
        let library = AphroditeLibrary(apps: [expected], selection: .init(provider: .openai, model: "gpt-test"))
        let store = TestStore(initialState: AphroditeReducer.State(
            apps: [original], selection: library.selection, storageState: .ready
        ).withModels([.openai: ["gpt-test"]])) { AphroditeReducer() } withDependencies: {
            $0.uuid = .constant(turnID)
            $0.date.now = editDate
            $0.modelProviderService.generateApp = { request in
                #expect(request.conversationID == conversationID)
                #expect(request.prompt.contains(completeHTML))
                #expect(request.prompt.contains("Add a reset button"))
                #expect(!request.prompt.contains("History 0"))
                #expect(!request.prompt.contains("History 1"))
                #expect(request.prompt.contains("History 2"))
                return generated
            }
            $0.aphroditePersistence.update = { replacement, expectedOld in
                #expect(replacement == expected)
                #expect(expectedOld == original)
                return library
            }
        }

        await store.send(.editTapped(appID)) { $0.editingAppID = appID }
        await store.send(.editPromptChanged("Add a reset button")) { $0.editPrompt = "Add a reset button" }
        await store.send(.sendEditTapped) { $0.isEditing = true }
        await store.receive(\.editFinished) {
            $0.isEditing = false
            $0.apps = [expected]
            $0.editPrompt = ""
        }
        await store.finish()
    }

    @MainActor
    @Test func cancelledEditCannotPersistALateResponseAndKeepsItsDraft() async {
        let app = AphroditeApp(id: UUID(), title: "Counter", html: completeHTML, createdAt: .distantPast, updatedAt: .distantPast)
        let continuation = LockIsolated<CheckedContinuation<String, Error>?>(nil)
        let store = TestStore(initialState: AphroditeReducer.State(
            apps: [app], selection: .init(provider: .openai, model: "gpt-test"), storageState: .ready
        ).withModels([.openai: ["gpt-test"]])) { AphroditeReducer() } withDependencies: {
            $0.uuid = .constant(UUID())
            $0.date.now = .distantPast
            $0.modelProviderService.generateApp = { _ in
                try await withCheckedThrowingContinuation { newContinuation in
                    continuation.withValue { $0 = newContinuation }
                }
            }
            $0.aphroditePersistence.update = { _, _ in
                Issue.record("Cancelled edit must not update persistence")
                return .init()
            }
        }

        await store.send(.editTapped(app.id)) { $0.editingAppID = app.id }
        await store.send(.editPromptChanged("Make it blue")) { $0.editPrompt = "Make it blue" }
        await store.send(.sendEditTapped) { $0.isEditing = true }
        await store.send(.cancelEditTapped) { $0.isEditing = false }
        continuation.withValue { $0?.resume(returning: updatedHTML) }
        await store.finish()
        #expect(store.state.apps == [app])
        #expect(store.state.editPrompt == "Make it blue")
    }

    @MainActor
    @Test func closingTheEditorCancelsALateResponseWithoutPersistingIt() async {
        let app = AphroditeApp(id: UUID(), title: "Counter", html: completeHTML, createdAt: .distantPast, updatedAt: .distantPast)
        let continuation = LockIsolated<CheckedContinuation<String, Error>?>(nil)
        let store = TestStore(initialState: AphroditeReducer.State(
            apps: [app], selection: .init(provider: .openai, model: "gpt-test"), storageState: .ready
        ).withModels([.openai: ["gpt-test"]])) { AphroditeReducer() } withDependencies: {
            $0.uuid = .constant(UUID())
            $0.date.now = .distantPast
            $0.modelProviderService.generateApp = { _ in
                try await withCheckedThrowingContinuation { newContinuation in
                    continuation.withValue { $0 = newContinuation }
                }
            }
            $0.aphroditePersistence.update = { _, _ in
                Issue.record("Closed editor must not update persistence")
                return .init()
            }
        }

        await store.send(.editTapped(app.id)) { $0.editingAppID = app.id }
        await store.send(.editPromptChanged("Make it blue")) { $0.editPrompt = "Make it blue" }
        await store.send(.sendEditTapped) { $0.isEditing = true }
        await store.send(.closeEditorTapped) {
            $0.editingAppID = nil
            $0.editPrompt = ""
            $0.isEditing = false
        }
        continuation.withValue { $0?.resume(returning: updatedHTML) }
        await store.finish()
        #expect(store.state.apps == [app])
    }

    @MainActor
    @Test func failedEditKeepsTheDraftAndSavedAppForRetry() async {
        let app = AphroditeApp(id: UUID(), title: "Counter", html: completeHTML, createdAt: .distantPast, updatedAt: .distantPast)
        let store = TestStore(initialState: AphroditeReducer.State(
            apps: [app], selection: .init(provider: .openai, model: "gpt-test"), storageState: .ready
        ).withModels([.openai: ["gpt-test"]])) { AphroditeReducer() } withDependencies: {
            $0.uuid = .constant(UUID())
            $0.date.now = .distantPast
            $0.modelProviderService.generateApp = { _ in throw AphroditeTestError.failed }
        }

        await store.send(.editTapped(app.id)) { $0.editingAppID = app.id }
        await store.send(.editPromptChanged("Make it blue")) { $0.editPrompt = "Make it blue" }
        await store.send(.sendEditTapped) { $0.isEditing = true }
        await store.receive(\.editGenerationFailed) {
            $0.isEditing = false
            $0.error = .generationFailed
        }
        #expect(store.state.apps == [app])
        #expect(store.state.editPrompt == "Make it blue")
        await store.finish()
    }

    @MainActor
    @Test func reloadingTheLibraryKeepsAnOpenEditorsTargetAndDraft() async {
        let app = AphroditeApp(id: UUID(), title: "Counter", html: completeHTML, createdAt: .distantPast, updatedAt: .distantPast)
        let library = AphroditeLibrary(apps: [app], selection: .init(provider: .openai, model: "gpt-test"))
        var initial = AphroditeReducer.State(apps: [app], selection: library.selection, storageState: .ready)
        initial.models = Dictionary(uniqueKeysWithValues: ModelProvider.allCases.map { ($0, ["gpt-test"]) })
        initial.editingAppID = app.id
        initial.editPrompt = "Make it blue"
        let store = TestStore(initialState: initial) { AphroditeReducer() } withDependencies: {
            $0.aphroditePersistence.load = { library }
        }

        await store.send(.reloadLibrary)
        await store.receive(\.libraryReloaded)
        #expect(store.state.editingAppID == app.id)
        #expect(store.state.editPrompt == "Make it blue")
        await store.finish()
    }
}

struct AphroditeSandboxDocumentTests {
    @Test func isolatesUntrustedDocumentInASandboxedSrcdocFrame() {
        let document = AphroditeSandboxDocument.make(from: completeHTML)

        #expect(document.contains("<iframe sandbox=\"allow-scripts\""))
        #expect(document.contains("srcdoc="))
        #expect(document.contains("default-src 'none'"))
        #expect(document.contains("connect-src 'none'"))
        #expect(document.contains("allow-same-origin") == false)
        #expect(document.contains("OnlySwitch") == false)
    }
}

#if os(macOS)
struct AphroditeIconRendererTests {
    @MainActor
    @Test func validatedStaticSVGProducesANativeImage() {
        #expect(AphroditeIconRenderer.image(svg: validIconSVG) != nil)
    }

    @MainActor
    @Test func missingOrUnsafeSVGProducesNoNativeImageForTheStarHexagonFallback() {
        #expect(AphroditeIconRenderer.image(svg: nil) == nil)
        #expect(AphroditeIconRenderer.image(svg: "<svg><script/></svg>") == nil)
    }
}


#endif

private enum AphroditeTestError: Error { case failed }

@MainActor
private func waitForWebKitReports(_ reports: LockIsolated<[CGFloat]>) {
    let deadline = Date().addingTimeInterval(5)
    while reports.withValue({ $0.count }) < 3, Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
}


private let completeHTML = "<!doctype html><html><head><title>Counter</title></head><body><button>0</button></body></html>"
private let updatedHTML = "<!doctype html><html><head><title>Counter Plus</title></head><body><button>Reset</button></body></html>"
private let validIconSVG = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\"><rect x=\"8\" y=\"8\" width=\"48\" height=\"48\" rx=\"8\" fill=\"#6750A4\"/></svg>"

private struct LegacyAphroditeApp: Codable {
    let id: UUID; let title: String; let html: String; let createdAt: Date; let updatedAt: Date
}

private struct IconBearingAphroditeApp: Codable {
    let id: UUID; let title: String; let html: String; let iconSVG: String?; let createdAt: Date; let updatedAt: Date
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private extension AphroditeReducer.State {
    func withModels(_ models: [ModelProvider: [String]]) -> Self {
        var state = self
        state.models = models
        return state
    }
}
