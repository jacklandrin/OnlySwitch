import ComposableArchitecture
import Extensions
import SwiftUI

@available(macOS 14.0, *)
public struct ClaudeUsageView: View {
    @Bindable private var store: StoreOf<ClaudeUsageReducer>
    private let managesScrolling: Bool
    public init(store: StoreOf<ClaudeUsageReducer>, managesScrolling: Bool = true) { self.store = store; self.managesScrolling = managesScrolling }
    public var body: some View {
        Group {
            if managesScrolling { ScrollView { content } } else { content }
        }
        .task { await store.send(.task).finish() }
        .onDisappear { store.send(.cancel) }
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Image("claude", bundle: .module)
                    .resizable().scaledToFit().frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Claude Usage".localized()).font(.title2.weight(.semibold))
                    if let account = store.snapshot?.account {
                        if let plan = account.plan {
                            Text(plan).font(.headline).accessibilityLabel("Current plan: %@".localizeWithFormat(arguments: plan))
                        }
                    } else {
                        Text("Uses your existing Claude Code session".localized()).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Refresh".localized(), systemImage: "arrow.clockwise") { store.send(.refreshTapped) }.disabled(store.isRefreshing)
            }
            if let account = store.snapshot?.account {
                // The email gets its own full-width row so long addresses do not wrap next to the Refresh button.
                Text(account.email ?? "Claude".localized())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, -12)
            }
            if let failure = store.failure {
                Label(message(failure), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                if store.canSignIn {
                    Button("Sign in with Claude Code".localized(), systemImage: "person.crop.circle.badge.checkmark") { store.send(.signInTapped) }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }
                if failure == .permissionDenied || (failure == .signedOut && !store.isSigningIn) {
                    keychainHint("Refresh reads your Claude Code sign-in from the macOS Keychain. macOS will ask for your Mac login password; choose “Always Allow” so usage can update automatically.".localized())
                }
            }
            if store.isSigningIn { signInProgress }
            if let signInFailure = store.signInFailure, !store.isSigningIn {
                Label(message(signInFailure), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            if store.isAwaitingKeychainAccess && store.isRefreshing {
                keychainHint("Waiting for Keychain access… Enter your Mac login password in the Keychain dialog and choose “Always Allow”. The dialog can take a moment to appear and may open behind other windows.".localized())
            }
            if let snapshot = store.snapshot {
                if store.isStale { Label("Showing the last successful update".localized(), systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                if let session = snapshot.session { quotaCard("Session (5-hour)".localized(), session) }
                if let weekly = snapshot.weekly { quotaCard("Weekly".localized(), weekly) }
                ForEach(snapshot.models) { model in
                    quotaCard(model.name + " · " + "Weekly".localized(), model.quota)
                }
                if snapshot.session == nil && snapshot.weekly == nil && snapshot.models.isEmpty {
                    Text("No usage limits were reported for this account.".localized()).foregroundStyle(.secondary)
                }
                extraCard(snapshot.extraUsage)
                Text("Updated %@".localizeWithFormat(arguments: snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened)))
                    .font(.footnote).foregroundStyle(.secondary)
            } else if store.isRefreshing {
                ProgressView("Loading Claude usage".localized()).frame(maxWidth: .infinity, minHeight: 180)
            } else if store.failure != nil {
                ContentUnavailableView("Claude usage unavailable".localized(), systemImage: "chart.bar.xaxis")
            }
        }.padding(24)
    }
    private var signInProgress: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ProgressView().controlSize(.small)
                if case .waitingForBrowser = store.signInPhase {
                    Text("Finish signing in in your browser. Usage refreshes automatically afterwards.".localized())
                } else {
                    Text("Starting Claude Code sign-in…".localized())
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                if case let .waitingForBrowser(url?) = store.signInPhase {
                    Link(destination: url) { Label("Open sign-in page".localized(), systemImage: "safari") }
                }
                Spacer()
                Button("Cancel".localized()) { store.send(.cancelSignInTapped) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
    private func message(_ failure: ClaudeSignInFailure) -> String {
        switch failure {
        case .cliNotFound: "Claude Code was not found on this Mac. Install Claude Code, then try again.".localized()
        case .failed: "Claude Code sign-in did not finish. Try again.".localized()
        case .timedOut: "Claude Code sign-in timed out. Try again.".localized()
        }
    }
    private func keychainHint(_ text: String) -> some View {
        Label(text, systemImage: "key")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
    private func quotaCard(_ title: String, _ quota: ClaudeQuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("%@ %@%% left".localizeWithFormat(arguments: title, quota.remainingPercent.formatted())).font(.headline)
            ProgressView(value: Double(quota.remainingPercent), total: 100).tint(.orange)
                .accessibilityLabel(title).accessibilityValue("%@%% remaining, %@".localizeWithFormat(arguments: quota.remainingPercent.formatted(), resetText(quota.resetAt)))
            Text(resetText(quota.resetAt)).foregroundStyle(.secondary)
        }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 12)).accessibilityElement(children: .combine)
    }
    private func extraCard(_ extra: ClaudeExtraUsage?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Extra usage".localized()).font(.headline)
            if let extra {
                if extra.isEnabled {
                    Text(extra.used.map { $0.formatted(.number.precision(.fractionLength(0 ... 2))) } ?? "Unavailable".localized()).font(.title3.weight(.semibold))
                    if let limit = extra.limit {
                        Text("of %@ %@".localizeWithFormat(arguments: limit.formatted(.number.precision(.fractionLength(0 ... 2))), extra.currency ?? ""))
                    }
                } else { Text("Extra usage is disabled.".localized()).foregroundStyle(.secondary) }
            } else { Text("Extra usage information is unavailable.".localized()).foregroundStyle(.secondary) }
        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
    private func resetText(_ date: Date?) -> String {
        date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Reset time unavailable".localized()
    }
    private func message(_ error: ClaudeUsageError) -> String {
        switch error {
        case .signedOut: "Sign in to Claude Code, then refresh usage.".localized()
        case .unauthorized: "Your Claude session needs to be refreshed.".localized()
        case .permissionDenied: "Allow Keychain access, then refresh usage.".localized()
        case .network: "Unable to refresh Claude usage.".localized()
        case .rateLimited: "Claude usage is rate limited. Try again later.".localized()
        case .invalidResponse: "Claude returned an unreadable usage response.".localized()
        case .unsupported: "No signed-in Claude Code installation was found.".localized()
        }
    }
}
