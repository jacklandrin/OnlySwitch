import ComposableArchitecture
import Extensions
import SwiftUI

@available(macOS 14.0, *)
public struct CodexUsageView: View {
    @Bindable private var store: StoreOf<CodexUsageReducer>

    public init(store: StoreOf<CodexUsageReducer>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Codex Usage".localized())
                            .font(.title2.weight(.semibold))
                        if let account = store.snapshot?.account {
                            Text(account.email ?? "Codex".localized())
                                .foregroundStyle(.secondary)
                            if let plan = account.plan {
                                Text("ChatGPT %@".localizeWithFormat(arguments: plan))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .accessibilityLabel("Current plan: %@".localizeWithFormat(arguments: plan))
                            }
                        } else {
                            Text("Uses your existing Codex or ChatGPT session".localized())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Refresh".localized(), systemImage: "arrow.clockwise") {
                        store.send(.refreshTapped)
                    }
                    .disabled(store.isRefreshing)
                }

                if store.isRefreshing && store.snapshot == nil {
                    ProgressView("Loading Codex usage".localized())
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if let snapshot = store.snapshot {
                    if store.isStale {
                        Label("Showing the last successful update".localized(), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }

                    if let session = snapshot.session {
                        quotaCard(title: "Session (5-hour)".localized(), window: session, tint: .teal)
                    }
                    if let weekly = snapshot.weekly {
                        quotaCard(title: "Weekly".localized(), window: weekly, tint: .blue)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Credits".localized())
                            .font(.headline)
                        switch snapshot.creditBalance {
                        case .unavailable:
                            Text("Credit balance is unavailable for this account.".localized())
                                .foregroundStyle(.secondary)
                        case .unlimited:
                            Label("Unlimited credits".localized(), systemImage: "infinity")
                        case let .available(remaining, limit, unit):
                            if let limit, limit > 0 {
                                ProgressView(value: min(remaining, limit), total: limit)
                                    .tint(.teal)
                            }
                            HStack(alignment: .firstTextBaseline) {
                                Text(
                                    "%@ left".localizeWithFormat(
                                        arguments: remaining.formatted(.number.precision(.fractionLength(0 ... 2)))
                                    )
                                )
                                    .font(.title3.weight(.semibold))
                                Spacer()
                                if let limit {
                                    Text(
                                        "of %@ %@".localizeWithFormat(
                                            arguments: limit.formatted(.number.notation(.compactName)), unit
                                        )
                                    )
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(unit.localized())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityElement(children: .combine)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Limit Reset Credits".localized())
                            .font(.headline)
                        switch snapshot.resetCredits {
                        case .unavailable:
                            Text("Reset-credit information is unavailable.".localized())
                                .foregroundStyle(.secondary)
                        case .unlimited:
                            Label("Unlimited".localized(), systemImage: "infinity")
                        case let .available(count, expiresAt):
                            Text("%@ available".localizeWithFormat(arguments: count.formatted()))
                                .font(.title3.weight(.semibold))
                            if let expiresAt {
                                Text(
                                    "Expires %@".localizeWithFormat(
                                        arguments: expiresAt.formatted(date: .abbreviated, time: .shortened)
                                    )
                                )
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityElement(children: .combine)

                    if let activity = store.activity {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Local Codex token estimates".localized())
                                .font(.headline)
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Today".localized()).foregroundStyle(.secondary)
                                    Text(activity.todayTokenCount.formatted(.number.notation(.compactName)))
                                        .font(.title3.weight(.semibold))
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("Last 30 days".localized()).foregroundStyle(.secondary)
                                    Text(activity.thirtyDayTokenCount.formatted(.number.notation(.compactName)))
                                        .font(.title3.weight(.semibold))
                                }
                            }
                            if activity.dailyUsage.isEmpty {
                                Text("No readable Codex token activity was found for the last 30 days.".localized())
                                    .foregroundStyle(.secondary)
                            } else {
                                GeometryReader { proxy in
                                    let maximum = max(activity.dailyUsage.map(\.tokenCount).max() ?? 1, 1)
                                    HStack(alignment: .bottom, spacing: 3) {
                                        ForEach(activity.dailyUsage) { day in
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(.teal)
                                                .frame(width: max((proxy.size.width - CGFloat(activity.dailyUsage.count * 3)) / CGFloat(activity.dailyUsage.count), 2), height: max(4, proxy.size.height * CGFloat(day.tokenCount) / CGFloat(maximum)))
                                        }
                                    }
                                }
                                .frame(height: 72)
                                .accessibilityLabel("Local Codex activity for the last 30 days".localized())
                                .accessibilityValue(
                                    "%@ active days and %@ tokens".localizeWithFormat(
                                        arguments: activity.dailyUsage.count.formatted(),
                                        activity.thirtyDayTokenCount.formatted()
                                    )
                                )
                            }
                            if activity.isPartial {
                                Label("Some local session files could not be included.".localized(), systemImage: "exclamationmark.triangle")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Usage history and cost estimates can be enabled separately after you review their privacy notice.".localized())
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Show local Codex usage estimates".localized(), systemImage: "chart.bar") {
                                store.send(.loadLocalActivityTapped)
                            }
                            .disabled(store.isLoadingActivity)
                        }
                    }
                } else if let failureMessage = store.failureMessage {
                    ContentUnavailableView(
                        "Codex usage unavailable".localized(),
                        systemImage: "chart.bar.xaxis",
                        description: Text(failureMessage)
                    )
                }
            }
            .padding(24)
        }
        .task { await store.send(.task).finish() }
    }

    @ViewBuilder
    private func quotaCard(title: String, window: CodexQuotaWindow, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(
                    "%@ %@%% left".localizeWithFormat(
                        arguments: title, window.remainingPercent.formatted()
                    )
                )
                    .font(.headline)
                Spacer()
                Text(resetText(window.resetAt))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(window.remainingPercent), total: 100)
                .tint(tint)
                .accessibilityLabel(title)
                .accessibilityValue(
                    "%@%% remaining, %@".localizeWithFormat(
                        arguments: window.remainingPercent.formatted(), resetText(window.resetAt)
                    )
                )
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func resetText(_ date: Date?) -> String {
        guard let date else { return "Reset time unavailable".localized() }
        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: .now, to: date)
        guard let day = components.day, let hour = components.hour, let minute = components.minute, day >= 0 else {
            return "Reset time unavailable".localized()
        }
        if day > 0 {
            return "Resets in %@d %@h".localizeWithFormat(
                arguments: day.formatted(), hour.formatted()
            )
        }
        return "Resets in %@h %@m".localizeWithFormat(
            arguments: hour.formatted(), minute.formatted()
        )
    }
}
