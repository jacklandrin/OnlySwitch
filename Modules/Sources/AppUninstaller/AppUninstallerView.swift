#if os(macOS)
import SwiftUI
import AppKit
import ComposableArchitecture
import Extensions

public struct AppUninstallerView: View {
    @Bindable private var store: StoreOf<AppUninstallerFeature>
    @State private var hostID = UUID()
    @State private var isTargeted = false
    private let managesScrolling: Bool
    private let compactPresentation: Bool
    public init(store: StoreOf<AppUninstallerFeature>, managesScrolling: Bool = true, compactPresentation: Bool = false) {
        self.store = store; self.managesScrolling = managesScrolling; self.compactPresentation = compactPresentation
    }
    public var body: some View {
        let pending = store.pendingConfirmation
        Group {
            if managesScrolling { ScrollView { content }.background(.background) }
            else { content }
        }
        .onAppear { store.send(.hostAppeared(hostID)) }
        .onDisappear { store.send(.hostDisappeared(hostID)) }
        .sheet(isPresented: Binding(get: { pending?.hostID == hostID }, set: { shown in
            if !shown, let pending { store.send(.cancelConfirmation(hostID: hostID, token: pending.token)) }
        })) {
            if let pending, pending.hostID == hostID {
                VStack(alignment: .leading, spacing: 16) {
                    Label("App Uninstaller Confirm Title".localized(), systemImage: "trash").font(.headline)
                    Text(store.snapshot?.displayName ?? "").font(.title3.bold())
                    Text("App Uninstaller Selected Count".localizeWithFormat(arguments: pending.itemIDs.count))
                    Text("App Uninstaller Confirm Message".localized()).fixedSize(horizontal: false, vertical: true)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(store.snapshot?.items.filter { pending.itemIDs.contains($0.id) } ?? []) { item in
                                Text(item.url.path).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 180)
                    HStack {
                        Spacer()
                        Button("App Uninstaller Cancel".localized()) { store.send(.cancelConfirmation(hostID: hostID, token: pending.token)) }.keyboardShortcut(.cancelAction)
                        Button("App Uninstaller Move To Trash".localized(), role: .destructive) { store.send(.confirmRemoval(hostID: hostID, token: pending.token)) }
                    }
                }.padding(24).frame(minWidth: 320, idealWidth: 440)
            }
        }
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: compactPresentation ? 14 : 20) {
            Label("App Uninstaller".localized(), systemImage: "trash.fill").font(compactPresentation ? .headline : .title2.bold())
            dropTarget
            if let error = store.error { failure(error) }
            if store.scanGeneration != nil {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("App Uninstaller Scanning".localized()).foregroundStyle(.secondary)
                    Spacer()
                    Button("App Uninstaller Cancel".localized()) { store.send(.cancelScanTapped) }
                }
            }
            if let snapshot = store.snapshot {
                if snapshot.items.isEmpty {
                    Label("App Uninstaller Complete".localized(), systemImage: "checkmark.circle").fixedSize(horizontal: false, vertical: true)
                } else {
                    inventory(snapshot)
                }
                if !snapshot.failures.isEmpty { failure(.init(key: "App Uninstaller Scan Partial")) }
            }
            if let result = store.lastRemovalResult {
                ForEach(Array(result.failures.enumerated()), id: \.offset) { _, issue in failure(issue) }
            }
            permissionCard
        }
        .padding(compactPresentation ? 12 : 24)
        .frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
    }
    private var dropTarget: some View {
        VStack(spacing: compactPresentation ? 10 : 14) {
            Image(systemName: "square.and.arrow.down").font(.system(size: compactPresentation ? 28 : 36, weight: .light)).foregroundStyle(.blue).accessibilityHidden(true)
            Text("App Uninstaller Drop Title".localized()).font(.headline)
            Text("App Uninstaller Drop Subtitle".localized()).font(.callout).foregroundStyle(.secondary)
            chooseApplicationButton
            Text("App Uninstaller Confirmation Notice".localized()).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(compactPresentation ? 18 : 30)
        .background(isTargeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.025), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [7, 5])))
        .disabled(store.isBusy)
        .dropDestination(for: URL.self) { urls, _ in
            guard !store.isBusy else { return false }
            guard urls.count == 1, let url = urls.first, url.isFileURL else { store.send(.invalidDrop); return false }
            store.send(.applicationChosen(url)); return true
        } isTargeted: { isTargeted = $0 }
    }
    @ViewBuilder private var chooseApplicationButton: some View {
        if #available(macOS 26.0, *) {
            Button { store.send(.chooseApplicationTapped) } label: {
                Label("App Uninstaller Choose App".localized(), systemImage: "plus.app")
            }.buttonStyle(.glassProminent)
        } else {
            Button { store.send(.chooseApplicationTapped) } label: {
                Label("App Uninstaller Choose App".localized(), systemImage: "plus.app")
            }.buttonStyle(.borderedProminent)
        }
    }
    private func inventory(_ snapshot: UninstallerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: snapshot.applicationURL.path)).resizable().frame(width: 40, height: 40).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.displayName).font(.headline)
                    Text(snapshot.bundleIdentifier).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Button("App Uninstaller Select All".localized()) { store.send(.selectAllTapped) }
                Button("App Uninstaller Select None".localized()) { store.send(.clearSelectionTapped) }
            }.controlSize(.small).disabled(store.isBusy)
            HStack(alignment: .firstTextBaseline) {
                Text("App Uninstaller Selected Count".localizeWithFormat(arguments: store.orderedSelectedIDs.count))
                Spacer()
                let selected = snapshot.items.filter { store.selectedItemIDs.contains($0.id) }
                Text(selected.contains(where: { $0.bytes == nil }) ? "App Uninstaller Unknown Size".localized() : Self.bytes(selected.compactMap(\.bytes).reduce(0, +)))
            }.font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(snapshot.items) { item in
                    row(item)
                    if item.id != snapshot.items.last?.id { Divider().padding(.horizontal, 12) }
                }
            }.modifier(UninstallerSurface())
            if store.removalGeneration != nil {
                HStack { ProgressView().controlSize(.small); Text("App Uninstaller Removing".localized()) }.foregroundStyle(.secondary)
            }
            Button("App Uninstaller Move To Trash".localized(), role: .destructive) { store.send(.removeTapped(hostID: hostID)) }
                .buttonStyle(.borderedProminent).disabled(store.isBusy || store.orderedSelectedIDs.isEmpty || store.pendingConfirmation != nil)
        }
    }
    private func row(_ item: UninstallerItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle(item.url.lastPathComponent, isOn: Binding(get: { store.selectedItemIDs.contains(item.id) }, set: { _ in store.send(.toggleSelection(item.id)) }))
                .toggleStyle(.checkbox).labelsHidden().accessibilityLabel(item.url.path).disabled(store.isBusy)
            VStack(alignment: .leading, spacing: 5) {
                Text(("App Uninstaller Kind " + item.kind.rawValue).localized()).font(.subheadline.weight(.semibold))
                Text(item.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(3).truncationMode(.middle).textSelection(.enabled).help(item.url.path)
                Text(item.bytes.map(Self.bytes) ?? "App Uninstaller Unknown Size".localized()).font(.caption).monospacedDigit()
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(12)
    }
    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("App Uninstaller Permission Notice".localized(), systemImage: "info.circle").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("App Uninstaller Open Privacy Settings".localized()) { store.send(.openPrivacySettingsTapped) }.controlSize(.small)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).modifier(UninstallerSurface())
    }
    private func failure(_ issue: UninstallerFailure) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(issue.key.localized(), systemImage: "exclamationmark.triangle").font(.callout)
            if let id = issue.itemID { Text(id).font(.caption).lineLimit(3).truncationMode(.middle).textSelection(.enabled) }
        }.foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.orange.opacity(0.08), in: .rect(cornerRadius: 12))
    }
    private static func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
}
private struct UninstallerSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.background(.regularMaterial, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.08)))
    }
}
#endif
