import ComposableArchitecture
import RemoteCore
import SwiftUI

struct RemoteCodexUsageView: View {
    let store: StoreOf<RemoteCodexUsageFeature>
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let error = store.error { errorView(error) }
                    if let snapshot = store.snapshot {
                        cards(snapshot, width: proxy.size.width)
                        Text("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if store.isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 64)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Show local Codex usage estimates", isOn: Binding(get: { store.includeLocalActivity }, set: { store.send(.localActivityOptInChanged($0)) }))
                        Text("When enabled, OnlySwitch reads local Codex session files on the selected Mac to estimate token usage. Chat contents and credentials stay on the Mac.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding()
                .padding(.bottom, RemotePageTabBar.contentBottomInset)
            }
            .refreshable { await store.send(.refreshTapped).finish() }
        }
        .navigationTitle("Codex Usage")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Codex Usage").font(.largeTitle.bold())
                Text("Remaining").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh", systemImage: "arrow.clockwise") { store.send(.refreshTapped) }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .tint(.secondary)
                .accessibilityLabel(Text("Refresh"))
                .disabled(store.isLoading || store.selectedMacID == nil || store.authenticatedSessionID == nil)
        }
    }

    @ViewBuilder
    private func cards(_ snapshot: RemoteCodexUsageSnapshot, width: CGFloat) -> some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 16) { cardGrid(snapshot, width: width) }
        } else {
            cardGrid(snapshot, width: width)
        }
    }

    private func cardGrid(_ snapshot: RemoteCodexUsageSnapshot, width: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: dynamicTypeSize.isAccessibilitySize ? 1 : RemoteCodexUsageLayout.columnCount(availableWidth: width, horizontalSizeClass: horizontalSizeClass)), spacing: 16) {
            card(
                "Account",
                value: snapshot.account.email ?? String(localized: "Codex"),
                detail: snapshot.account.plan.map { String(localized: "ChatGPT \($0)") },
                emphasizesDetail: true
            )
            quotaCard("Session (5-hour)", snapshot.session)
            quotaCard("Weekly", snapshot.weekly)
            card("Credits", value: RemoteCodexUsagePresentation.credits(snapshot.creditBalance))
            resetCreditsCard(snapshot.resetCredits)
            if let activity = snapshot.activity { activityCard(activity) }
        }
    }

    private func quotaCard(_ title: LocalizedStringKey, _ quota: CodexQuotaWindowDTO?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(RemoteCodexUsagePresentation.percentage(quota)).font(.title2.bold())
            if let quota {
                ProgressView(value: Double(quota.remainingPercent), total: 100).tint(.teal)
                Text(quota.resetAt.map { String(localized: "Resets \($0.formatted(date: .abbreviated, time: .shortened))") } ?? String(localized: "Reset time unavailable"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, minHeight: 96, alignment: .leading).padding().remoteCodexCardSurface()
    }
    private func card(
        _ title: LocalizedStringKey,
        value: String,
        detail: String? = nil,
        emphasizesDetail: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).textSelection(.enabled)
            if let detail {
                Text(detail)
                    .font(emphasizesDetail ? .footnote.weight(.bold) : .footnote)
                    .foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, minHeight: 96, alignment: .leading).padding().remoteCodexCardSurface()
    }
    private func resetCredits(_ value: CodexResetCreditsDTO) -> String {
        switch value {
        case .unavailable: String(localized: "Unavailable")
        case .unlimited: String(localized: "Unlimited")
        case let .available(count, _): count.formatted()
        }
    }
    private func resetCreditsCard(_ value: CodexResetCreditsDTO) -> some View {
        let detail: String? = if case let .available(_, expiresAt) = value {
            expiresAt.map { String(localized: "Expires \($0.formatted(date: .abbreviated, time: .shortened))") }
        } else { nil }
        return card("Limit Reset Credits", value: resetCredits(value), detail: detail)
    }
    private func activityCard(_ value: CodexActivityEstimateDTO) -> some View {
        let total = value.dailyUsage.reduce(0) { $0 + $1.tokenCount }
        let today = value.dailyUsage.last(where: { Calendar.current.isDateInToday($0.date) })?.tokenCount ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            Text("Local Codex token estimates").font(.headline)
            HStack {
                VStack(alignment: .leading) { Text("Today").foregroundStyle(.secondary); Text(today.formatted(.number.notation(.compactName))).font(.title3.bold()) }
                Spacer()
                VStack(alignment: .trailing) { Text("Last 30 days").foregroundStyle(.secondary); Text(total.formatted(.number.notation(.compactName))).font(.title3.bold()) }
            }
            if value.dailyUsage.isEmpty {
                Text("No readable Codex token activity was found for the last 30 days.").foregroundStyle(.secondary)
            } else {
                GeometryReader { proxy in
                    let maximum = max(value.dailyUsage.map(\.tokenCount).max() ?? 1, 1)
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(value.dailyUsage) { day in
                            RoundedRectangle(cornerRadius: 2).fill(.teal)
                                .frame(height: max(4, proxy.size.height * CGFloat(day.tokenCount) / CGFloat(maximum)))
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: 72)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Local Codex activity for the last 30 days")
                .accessibilityValue(String(localized: "\(value.dailyUsage.count) active days and \(total) tokens"))
            }
            if value.isPartial { Label("Some local session files could not be included.", systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, minHeight: 96, alignment: .leading).padding().remoteCodexCardSurface()
    }
    private func errorView(_ error: RemoteCodexUsageErrorPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.title, systemImage: "exclamationmark.triangle.fill").font(.headline)
            Text(error.message).foregroundStyle(.secondary)
            if error.allowsRetry { Button("Try Again") { store.send(.refreshTapped) }.buttonStyle(.borderedProminent) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding().remoteCodexCardSurface()
    }
}
