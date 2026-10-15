import ComposableArchitecture
import OnlyAgent
import SwiftUI
import Defines
import Extensions

@available(macOS 26.0, *)
public struct AphroditeSettingsView: View {
    @State private var store: StoreOf<AphroditeReducer>
    @AppStorage(UserDefaults.Key.showAphroditeTab) private var isVisible = true
    public init(store: StoreOf<AphroditeReducer> = Store(initialState: .init()) { AphroditeReducer() }) { _store = State(initialValue: store) }

    public var body: some View {
        Group {
            if let id = store.editingAppID, let app = store.apps[id: id] { AphroditeEditorView(store: store, app: app) }
            else { libraryForm }
        }
        .task { store.send(.task) }
        .onReceive(NotificationCenter.default.publisher(for: .aphroditeLibraryChanged).receive(on: RunLoop.main)) { _ in store.send(.reloadLibrary) }
        .onDisappear { if store.editingAppID != nil { store.send(.editorDisappeared) } }
    }

    private var libraryForm: some View {
        Form {
            Toggle("Show Aphrodite tab".localized(), isOn: $isVisible)
                .onChange(of: isVisible) { _ in NotificationCenter.default.post(name: .changeSettings, object: nil) }
            Section("Create a mini app".localized()) {
                TextEditor(text: Binding(get: { store.prompt }, set: { store.send(.promptChanged($0)) }))
                    .frame(minHeight: 100).accessibilityLabel("Describe your mini app".localized())
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
            }
            Section("Saved mini apps".localized()) {
                if store.apps.isEmpty { ContentUnavailableView("No mini apps yet".localized(), systemImage: "sparkles.rectangle.stack", description: Text("Describe an app above to create it.".localized())) }
                ForEach(store.apps) { app in
                    HStack {
                        Button { store.send(.editTapped(app.id)) } label: {
                            HStack {
                                AphroditeIconView(svg: app.iconSVG).frame(width: 24, height: 24)
                                Text(app.title)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isGenerating)
                        Button("Delete".localized(), systemImage: "trash", role: .destructive) { store.send(.deleteTapped(app.id)) }.labelStyle(.iconOnly)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var hasValidSelection: Bool {
        guard let selection = store.selection else { return false }
        return store.models[selection.provider]?.contains(selection.model) == true
    }
}

@available(macOS 26.0, *)
public struct AphroditePanelView: View {
    @State private var store: StoreOf<AphroditeReducer>
    @State private var webContentHeight: CGFloat = 240
    public init(store: StoreOf<AphroditeReducer> = Store(initialState: .init()) { AphroditeReducer() }) { _store = State(initialValue: store) }
    public var body: some View {
        Group {
            if let id = store.selectedAppID, let app = store.apps[id: id] {
                VStack(spacing: 8) {
                    HStack { Button("Back".localized(), systemImage: "chevron.left") { store.send(.selectApp(nil)) }; Text(app.title).font(.headline); Spacer() }.padding(.horizontal)
                    #if os(macOS)
                    SecureAphroditeWebView(html: app.html, onContentHeightChange: { webContentHeight = $0 })
                        .frame(height: webContentHeight)
                    #endif
                }
            } else if store.storageState == .failed {
                VStack(spacing: 12) {
                    ContentUnavailableView("Aphrodite could not load your saved apps.".localized(), systemImage: "exclamationmark.triangle")
                    Button("Retry".localized()) { store.send(.reloadLibrary) }
                }
            } else if store.apps.isEmpty {
                ContentUnavailableView("No mini apps yet".localized(), systemImage: "sparkles.rectangle.stack", description: Text("Create one in Aphrodite Settings.".localized()))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(store.apps) { app in
                            Button { store.send(.selectApp(app.id)) } label: {
                                HStack(spacing: 10) {
                                    AphroditeIconView(svg: app.iconSVG).frame(width: 28, height: 28)
                                    Text(app.title)
                                }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .task { store.send(.task) }
        .onReceive(NotificationCenter.default.publisher(for: .aphroditeLibraryChanged).receive(on: RunLoop.main)) { _ in store.send(.reloadLibrary) }
    }
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
