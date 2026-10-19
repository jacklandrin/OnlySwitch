import ComposableArchitecture
import RemoteCore
import SwiftUI

struct RemoteClaudeUsageView: View {
    let store: StoreOf<RemoteClaudeUsageFeature>
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Claude Usage").font(.largeTitle.bold())
                        Spacer()
                        Button("Refresh", systemImage: "arrow.clockwise") { store.send(.refreshTapped) }
                            .labelStyle(.iconOnly).buttonStyle(.bordered).tint(.secondary)
                            .disabled(store.isLoading || store.selectedMacID == nil || store.authenticatedSessionID == nil)
                    }
                    if let error = store.error { errorView(error) }
                    if let snapshot = store.snapshot {
                        if store.isStale { Label("Showing the last successful update", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                        if #available(iOS 26, *) {
                            GlassEffectContainer(spacing: 16) { cards(snapshot, width: proxy.size.width) }
                        } else { cards(snapshot, width: proxy.size.width) }
                        Text("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))").font(.footnote).foregroundStyle(.secondary)
                    } else if store.isLoading { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 64) }
                }.padding().padding(.bottom, RemotePageTabBar.contentBottomInset)
            }.refreshable { await store.send(.refreshTapped).finish() }
        }.navigationTitle("Claude Usage")
    }
    private func cards(_ snapshot: RemoteClaudeUsageSnapshot, width: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: dynamicTypeSize.isAccessibilitySize ? 1 : RemoteClaudeUsageLayout.columnCount(availableWidth: width, horizontalSizeClass: horizontalSizeClass)), spacing: 16) {
            card("Account", value: snapshot.account.email ?? String(localized: "Claude"), detail: snapshot.account.plan)
            if let session = snapshot.session { quotaCard(String(localized: "Session (5-hour)"), session) }
            if let weekly = snapshot.weekly { quotaCard(String(localized: "Weekly"), weekly) }
            ForEach(snapshot.models) { model in
                quotaCard(model.name + " · " + String(localized: "Weekly"), model.quota)
            }
            if snapshot.session == nil && snapshot.weekly == nil && snapshot.models.isEmpty {
                Text("No usage limits were reported for this account.").foregroundStyle(.secondary)
            }
            card("Extra usage", value: RemoteClaudeUsagePresentation.extra(snapshot.extraUsage))
        }
    }
    private func quotaCard(_ title: String, _ quota: ClaudeQuotaWindowDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(RemoteClaudeUsagePresentation.percentage(quota)).font(.title2.bold())
            ProgressView(value: Double(quota.remainingPercent), total: 100).tint(.orange)
            Text(quota.resetAt.map { String(localized: "Resets \($0.formatted(date: .abbreviated, time: .shortened))") } ?? String(localized: "Reset time unavailable"))
                .font(.footnote).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, minHeight: 96, alignment: .leading).padding().remoteCodexCardSurface().accessibilityElement(children: .combine)
    }
    private func card(_ title: LocalizedStringKey, value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).textSelection(.enabled)
            if let detail { Text(detail).font(.footnote.weight(.bold)).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, minHeight: 96, alignment: .leading).padding().remoteCodexCardSurface()
    }
    private func errorView(_ error: RemoteClaudeUsageErrorPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.title, systemImage: "exclamationmark.triangle.fill").font(.headline)
            Text(error.message).foregroundStyle(.secondary)
            if error.allowsRetry { Button("Try Again") { store.send(.refreshTapped) }.buttonStyle(.borderedProminent) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding().remoteCodexCardSurface()
    }
}
