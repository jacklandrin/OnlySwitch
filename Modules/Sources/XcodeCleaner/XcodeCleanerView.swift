#if os(macOS)
import SwiftUI
import ComposableArchitecture
import Extensions

public struct XcodeCleanerView: View {
    @Bindable private var store: StoreOf<XcodeCleanerFeature>
    @State private var hostID = UUID()
    private let managesScrolling: Bool
    private let compactPresentation: Bool
    public init(store: StoreOf<XcodeCleanerFeature>, managesScrolling: Bool = true, compactPresentation: Bool = false) {
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
        .sheet(isPresented: Binding(get: { pending?.hostID == hostID }, set: { presented in
            if !presented, let pending { store.send(.cancelBatch(token: pending.token, hostID: hostID)) }
        })) {
            if let pending, pending.hostID == hostID {
                CleanerBatchConfirmationView(items: store.confirmationItems,
                    confirm: { store.send(.confirmBatch(token: pending.token, hostID: hostID)) },
                    cancel: { store.send(.cancelBatch(token: pending.token, hostID: hostID)) })
            }
        }
    }
    private var content: some View {
            VStack(alignment: .leading, spacing: compactPresentation ? 14 : 20) {
                header
                summary
                selectionToolbar
                if let refreshError = store.refreshError { failure(refreshError) }
                if store.isStale { notice("Xcode Cleaner Stale Results", symbol: "arrow.clockwise") }
                if let error = store.error { failure(error) }
                if let outcome = store.lastCleanupResult {
                    if !outcome.removedItemIDs.isEmpty { notice("Xcode Cleaner Completed", symbol: "checkmark.circle.fill") }
                    ForEach(Array(outcome.failures.enumerated()), id: \.offset) { _, error in failure(error) }
                }
                if let snapshot = store.snapshot {
                    section("Xcode Cleaner Caches", items: snapshot.items.filter { $0.category != .simulatorDevice && $0.category != .simulatorRuntime })
                    deviceSections(items: snapshot.items)
                    section("Xcode Cleaner Runtimes", items: snapshot.items.filter { $0.category == .simulatorRuntime })
                    ForEach(Array(snapshot.failures.enumerated()), id: \.offset) { _, error in failure(error) }
                } else if !store.isBusy {
                    ContentUnavailableView("Xcode Cleaner Empty".localized(), systemImage: "hammer.circle", description: Text("Xcode Cleaner Standard Locations".localized()))
                }
                Text("Xcode Cleaner Standard Locations".localized()).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(compactPresentation ? 12 : 24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
    }
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { headerTitle; Spacer(minLength: 8); scanButton }
            VStack(alignment: .leading, spacing: 10) { headerTitle; scanButton }
        }
    }
    private var headerTitle: some View {
        HStack(spacing: 12) {
            Image(systemName: "hammer.fill").font(.system(size: compactPresentation ? 20 : 28)).foregroundStyle(.blue)
                .frame(width: compactPresentation ? 38 : 52, height: compactPresentation ? 38 : 52)
                .background(.blue.opacity(0.1), in: .rect(cornerRadius: 12)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Xcode Cleaner".localized()).font(compactPresentation ? .headline : .title2.bold())
                if !compactPresentation {
                    Text("Xcode Cleaner Standard Locations".localized()).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    @ViewBuilder private var scanButton: some View {
        if store.activity == .scanning {
            Button("Cancel".localized()) { store.send(.cancelScanTapped) }
        } else {
            Button { store.send(.scanTapped) } label: {
                Label((store.snapshot == nil ? "Xcode Cleaner Scan" : "Xcode Cleaner Rescan").localized(), systemImage: "arrow.clockwise")
            }.buttonStyle(.borderedProminent).disabled(store.isBusy)
        }
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label((store.isEstimated ? "Xcode Cleaner Estimated Remaining" : "Xcode Cleaner Known Storage").localized(), systemImage: "internaldrive").foregroundStyle(.secondary)
                Spacer()
                if store.isBusy || store.isRefreshing { ProgressView().controlSize(.small) }
            }
            Text(store.snapshot.map { Self.bytes($0.knownBytes) } ?? "—").font(.system(size: compactPresentation ? 28 : 34, weight: .semibold, design: .rounded)).monospacedDigit()
            if store.activity == .scanning { Text("Xcode Cleaner Scanning".localized()).foregroundStyle(.secondary) }
            else if case .cleaning = store.activity { Text("Xcode Cleaner Cleaning".localized()).foregroundStyle(.secondary) }
            if store.isRefreshing { Text("Xcode Cleaner Refreshing".localized()).font(.caption).foregroundStyle(.secondary) }
            if store.snapshot?.hasUnknownBytes == true { Text("Xcode Cleaner Partial Size".localized()).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(compactPresentation ? 12 : 18).modifier(CleanerSurface())
    }
    private var selectionToolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack { selectionButtons; Spacer(minLength: 8); cleanSelectedButton }
                VStack(alignment: .leading, spacing: 10) { selectionButtons; cleanSelectedButton }
            }
            if !store.selectedItemIDs.isEmpty {
                let selectedItems = store.snapshot?.items.filter { store.selectedItemIDs.contains($0.id) } ?? []
                HStack {
                    Text("Xcode Cleaner Selected Count".localizeWithFormat(arguments: selectedItems.count))
                    Spacer(minLength: 8)
                    Text(Self.bytes(selectedItems.compactMap(\.bytes).reduce(0, +)))
                }.font(.caption).foregroundStyle(.secondary)
                if selectedItems.contains(where: { $0.bytes == nil }) { Text("Xcode Cleaner Partial Size".localized()).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
    private var selectionButtons: some View {
        HStack(spacing: 12) {
            Button("Xcode Cleaner Select All".localized()) { store.send(.selectAllTapped) }
                .disabled(store.snapshot?.items.contains(where: \.canClean) != true)
            Button("Xcode Cleaner Clear Selection".localized()) { store.send(.clearSelectionTapped) }
                .disabled(store.selectedItemIDs.isEmpty)
        }.controlSize(.small)
    }
    private var cleanSelectedButton: some View {
        Button("Xcode Cleaner Clean Selected".localizeWithFormat(arguments: store.orderedSelectedIDs.count)) {
            store.send(.cleanSelectedInHost(hostID))
        }
        .buttonStyle(.borderedProminent)
        .disabled(store.orderedSelectedIDs.isEmpty || store.isBusy || store.isStale)
    }
    private func deviceSections(items: [CleanerItem]) -> some View {
        let groups = CleanerDeviceGroup.groups(items: items)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Xcode Cleaner Devices".localized()).font(.headline)
            if groups.isEmpty { Text("Xcode Cleaner Empty".localized()).font(.callout).foregroundStyle(.secondary) }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 0) {
                    Text(group.runtimeIdentifier == nil ? group.title.localized() : group.title)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).padding(14)
                    Divider().padding(.horizontal, 14)
                    ForEach(group.items) { item in
                        row(item)
                        if item.id != group.items.last?.id { Divider().padding(.horizontal, 14) }
                    }
                }.modifier(CleanerSurface())
            }
        }
    }
    private func section(_ title: String, items: [CleanerItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.localized()).font(.headline)
            if items.isEmpty { Text("Xcode Cleaner Empty".localized()).font(.callout).foregroundStyle(.secondary).padding(.vertical, 6) }
            else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        row(item)
                        if item.id != items.last?.id { Divider().padding(.horizontal, 14) }
                    }
                }.modifier(CleanerSurface())
            }
        }
    }
    private func row(_ item: CleanerItem) -> some View {
        Group {
            if compactPresentation {
                VStack(alignment: .leading, spacing: 10) { rowDetails(item); cleanButton(item).frame(maxWidth: .infinity, alignment: .trailing) }
            } else {
                HStack(alignment: .top, spacing: 12) { rowDetails(item); cleanButton(item) }
            }
        }.padding(14)
    }
    private func rowDetails(_ item: CleanerItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(itemTitle(item), isOn: Binding(get: { store.selectedItemIDs.contains(item.id) }, set: { store.send(.selectionChanged(itemID: item.id, isSelected: $0)) }))
                .toggleStyle(.checkbox).labelsHidden().accessibilityLabel(itemTitle(item)).disabled(!item.canClean)
            Image(systemName: symbol(item.category)).foregroundStyle(.blue).font(.title3).frame(width: 24).padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(itemTitle(item)).font(.headline).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if item.category == .derivedData { Text("Xcode Cleaner Derived Data Detail".localized()).font(.caption).foregroundStyle(.secondary) }
                if let status = item.statusKey { Text(status.localized()).font(.caption).foregroundStyle(.secondary) }
                Text(item.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(3).truncationMode(.middle)
                Text(item.bytes.map(Self.bytes) ?? "Xcode Cleaner Unknown Size".localized()).font(.callout.weight(.medium)).monospacedDigit()
                if let issue = store.lastCleanupResult?.failures.first(where: { $0.itemID == item.id }) {
                    Label(issue.key.localized(), systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func cleanButton(_ item: CleanerItem) -> some View {
        Button((item.requiresConfirmation ? "Xcode Cleaner Delete" : "Xcode Cleaner Clean").localized(), role: item.requiresConfirmation ? .destructive : nil) { store.send(.cleanTappedInHost(itemID: item.id, hostID: hostID)) }
            .disabled(!item.canClean || store.isBusy || store.isStale)
            .accessibilityLabel(Text((item.requiresConfirmation ? "Xcode Cleaner Delete" : "Xcode Cleaner Clean").localized() + ": " + itemTitle(item)))
    }
    private func itemTitle(_ item: CleanerItem) -> String {
        (item.category == .simulatorDevice || item.category == .simulatorRuntime) ? item.title : item.title.localized()
    }
    private func notice(_ key: String, symbol: String) -> some View {
        Label(key.localized(), systemImage: symbol).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    private func failure(_ error: CleanerFailure) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(error.key.localized(), systemImage: "exclamationmark.triangle").font(.callout.weight(.medium))
            if let detail = error.detail { Text(detail).font(.caption).textSelection(.enabled).lineLimit(5) }
        }.foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.orange.opacity(0.08), in: .rect(cornerRadius: 12))
    }
    private static func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
    private func symbol(_ category: CleanerCategory) -> String {
        switch category {
        case .simulatorDevice: "iphone"
        case .simulatorRuntime: "shippingbox"
        case .deviceSupport: "cable.connector"
        case .simulatorLogs: "doc.text"
        default: "folder"
        }
    }
}
private struct CleanerSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) { content.glassEffect(.regular, in: .rect(cornerRadius: 16)) }
        else { content.background(.regularMaterial, in: .rect(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.08))) }
    }
}
#endif
