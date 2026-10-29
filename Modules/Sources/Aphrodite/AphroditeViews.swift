import ComposableArchitecture
import OnlyAgent
import SwiftUI
import UniformTypeIdentifiers
import Defines
import Extensions

@available(macOS 26.0, *)
public struct AphroditeSettingsView: View {
    private let store: StoreOf<AphroditeReducer>
    @Environment(\.colorScheme) private var colorScheme
    public init(store: StoreOf<AphroditeReducer>) { self.store = store }

    public var body: some View {
        Group {
            if let id = store.editingAppID, let app = store.apps[id: id] { AphroditeEditorView(store: store, app: app) }
            else { libraryForm }
        }
        .task { store.send(.task) }
        .onReceive(NotificationCenter.default.publisher(for: .aphroditeLibraryChanged).receive(on: RunLoop.main)) { _ in store.send(.reloadLibrary) }
    }

    private var libraryForm: some View {
        Form {
            Section {
                TextEditor(text: Binding(get: { store.prompt }, set: { store.send(.promptChanged($0)) }))
                    .aphroditeTextEditorInset()
                    .frame(minHeight: 100)
                    .accessibilityLabel("Describe your mini app".localized())
                Picker("Provider".localized(), selection: Binding(get: { store.selection?.provider ?? .openai }, set: { store.send(.providerSelected($0)) })) {
                    ForEach(ModelProvider.allCases, id: \.self) { Text($0.aphroditeDisplayName).tag($0) }
                }
                Picker("Model".localized(), selection: Binding(get: { store.selection?.model ?? "" }, set: { store.send(.modelSelected($0)) })) {
                    ForEach(store.models[store.selection?.provider ?? .openai] ?? [], id: \.self) { Text($0).tag($0) }
                }
                let selectedProvider = store.selection?.provider ?? .openai
                if store.modelLoadErrors[selectedProvider] != nil {
                    HStack { Text("Models could not be loaded for this provider.".localized()).foregroundStyle(.red); Button("Retry".localized()) { store.send(.loadModels(selectedProvider)) } }
                }
                HStack {
                    if store.isGenerating { ProgressView(); Button("Cancel".localized()) { store.send(.cancelGenerationTapped) } }
                    else { Button("Generate".localized()) { store.send(.generateTapped) }.disabled(store.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.storageState != .ready || !hasValidSelection) }
                }
                if let error = store.error {
                    HStack {
                        Text(error.rawValue.localized()).foregroundStyle(.red).accessibilityLabel(error.rawValue.localized())
                        if error == .storageLoadFailed {
                            Button("Retry".localized()) { store.send(.reloadLibrary) }
                        }
                    }
                }
            } header: {
                AphroditeSectionHeader("Create a mini app".localized(), systemImage: "wand.and.stars")
            }
            Section {
                Button("Import mini app".localized(), systemImage: "square.and.arrow.down") {
                    store.send(.importTapped)
                }
                .disabled(store.storageState != .ready)
                if store.apps.isEmpty { ContentUnavailableView("No mini apps yet".localized(), systemImage: "sparkles.rectangle.stack", description: Text("Describe an app above to create it.".localized())) }
                ForEach(store.apps) { app in
                    AphroditeLibraryCard(
                        app: app,
                        isOpenDisabled: store.isGenerating || (store.activeEdit != nil && store.activeEdit?.appID != app.id)
                    ) {
                        store.send(.editTapped(app.id))
                    } actions: {
                        ShareLink(
                            item: AphroditeSharePayload(app: app),
                            preview: SharePreview(app.title, image: sharePreviewImage(for: app))
                        ) {
                            Label("Share mini app".localized(), systemImage: "square.and.arrow.up")
                                .labelStyle(.iconOnly)
                        }
                        .accessibilityLabel("Share mini app".localized())
                        .accessibilityValue(app.title)
                        Button("Delete".localized(), systemImage: "trash", role: .destructive) { store.send(.deleteTapped(app.id)) }.labelStyle(.iconOnly)
                    }
                }
            } header: {
                AphroditeSectionHeader("Saved mini apps".localized(), systemImage: "square.grid.2x2")
            }
        }
        .formStyle(.grouped)
        .tint(colorScheme == .dark ? .mint : .accentColor)
        .fileImporter(isPresented: Binding(
            get: { store.isImporting },
            set: { if !$0 { store.send(.importPickerDismissed) } }
        ), allowedContentTypes: [.aphroditeMiniApp], allowsMultipleSelection: false) { result in
            importDocument(result)
        }
        .alert("Import failed".localized(), isPresented: Binding(
            get: { store.importError != nil },
            set: { if !$0 { store.send(.importErrorDismissed) } }
        )) {
            Button("OK".localized()) { store.send(.importErrorDismissed) }
        } message: {
            Text(store.importError?.rawValue.localized() ?? "This mini app could not be imported.".localized())
        }
    }

    private var hasValidSelection: Bool {
        guard let selection = store.selection else { return false }
        return store.models[selection.provider]?.contains(selection.model) == true
    }

    private func importDocument(_ result: Result<[URL], any Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { throw AphroditeShareDocument.ValidationError.malformedDocument }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard fileSize <= AphroditeShareDocument.maximumEncodedBytes else {
                throw AphroditeShareDocument.ValidationError.documentTooLarge
            }
            store.send(.importDocument(try Data(contentsOf: url, options: [.mappedIfSafe])))
        } catch {
            store.send(.importFinished(.failure(error)))
        }
    }

    private func sharePreviewImage(for app: AphroditeApp) -> Image {
        #if os(macOS)
        if let image = AphroditeIconRenderer.image(svg: app.iconSVG) { return Image(nsImage: image) }
        #endif
        return Image(systemName: "sparkles.rectangle.stack")
    }
}

@available(macOS 26.0, *)
public struct AphroditePanelView: View {
    private let store: StoreOf<AphroditeReducer>
    private let maximumRunningHeight: CGFloat?
    @State private var webContentHeight: CGFloat = 240
    @State private var runningHeaderHeight: CGFloat = 0
    public init(store: StoreOf<AphroditeReducer>, maximumRunningHeight: CGFloat? = nil) {
        self.store = store
        self.maximumRunningHeight = maximumRunningHeight
    }
    public var body: some View {
        Group {
            if let id = store.selectedAppID, let app = store.apps[id: id] {
                VStack(spacing: 8) {
                    HStack { Button("Back".localized(), systemImage: "chevron.left") { store.send(.selectApp(nil)) }; Text(app.title).font(.headline); Spacer() }
                        .padding()
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: AphroditeRunningHeaderHeightKey.self, value: proxy.size.height)
                        })
                    #if os(macOS)
                    SecureAphroditeWebView(app: app, onContentHeightChange: { webContentHeight = $0 })
                        .frame(height: runningWebViewHeight)
                    #endif
                }
                .aphroditePanelSurface()
                .onPreferenceChange(AphroditeRunningHeaderHeightKey.self) { runningHeaderHeight = $0 }
            } else if store.storageState == .failed {
                VStack(spacing: 12) {
                    ContentUnavailableView("Aphrodite could not load your saved apps.".localized(), systemImage: "exclamationmark.triangle")
                    Button("Retry".localized()) { store.send(.reloadLibrary) }
                }
            } else if store.apps.isEmpty {
                ContentUnavailableView("No mini apps yet".localized(), systemImage: "sparkles.rectangle.stack", description: Text("Create one in Aphrodite Settings.".localized()))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(store.apps) { app in
                            AphroditeLibraryCard(app: app) {
                                store.send(.selectApp(app.id))
                            } actions: {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .task { store.send(.reloadLibrary) }
        .onReceive(NotificationCenter.default.publisher(for: .aphroditeLibraryChanged).receive(on: RunLoop.main)) { _ in store.send(.reloadLibrary) }
    }

    private var runningWebViewHeight: CGFloat {
        guard let maximumRunningHeight, maximumRunningHeight.isFinite else { return webContentHeight }
        return min(webContentHeight, max(1, maximumRunningHeight - runningHeaderHeight - 8))
    }
}

private struct AphroditeRunningHeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

public struct AphroditeUnavailableView: View {
    public init() {}
    public var body: some View { ContentUnavailableView("Aphrodite requires macOS 26 or later".localized(), systemImage: "sparkles.rectangle.stack") }
}

extension ModelProvider {
    var aphroditeDisplayName: String {
        self == .openai ? "OpenAI" : rawValue.capitalized
    }
}
