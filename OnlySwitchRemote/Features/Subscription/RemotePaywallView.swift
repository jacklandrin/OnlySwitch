import ComposableArchitecture
import SwiftUI

struct RemotePaywallView: View {
    let store: StoreOf<RemotePaywallFeature>
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let privacyURL = URL(string: "https://onlyswitch.click/#/privacy-policy")!
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        NavigationStack {
            ZStack {
                paywallBackground
                ScrollView {
                    VStack(spacing: 20) {
                        hero
                        serviceCard
                        priceCard
                        billingCard
                        actionCard
                        legalLinks
                    }
                    .frame(maxWidth: 620)
                    .padding()
                }
            }
            .navigationTitle("OnlyRemote Plus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .accessibilityHint("Closes the OnlyRemote Plus preview")
                }
            }
        }
        .task { await store.send(.task).finish() }
    }

    private var paywallBackground: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.22), Color.purple.opacity(0.12), Color(.systemBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var hero: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("OnlyRemote Plus")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("Subscription Preview")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Aphrodite is not available in this version. Subscriptions cannot be purchased yet.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var serviceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Aphrodite personal tools", systemImage: "wand.and.stars")
                .font(.title3.bold())
            Text("Use your personal Aphrodite tools in OnlyRemote when Aphrodite becomes available.")
                .foregroundStyle(.secondary)
            Label("Aphrodite is not available in this version.", systemImage: "clock.badge.exclamationmark")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paywallCard(reduceTransparency: reduceTransparency)
    }

    private var priceCard: some View {
        VStack(spacing: 8) {
            if store.isLoading {
                ProgressView("Loading Subscription")
            } else if let price = store.product?.displayPrice {
                Text(price)
                    .font(.system(.largeTitle, design: .rounded).bold())
                    .foregroundStyle(.primary)
                Text("When available, this subscription will renew automatically at \(price) per month until canceled.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
            } else {
                Text("Price unavailable")
                    .font(.title2.bold())
            }
            Text("1 month · auto-renewable")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .paywallCard(reduceTransparency: reduceTransparency)
    }

    private var billingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Billing and cancellation")
                .font(.headline)
            Text("When subscriptions become available, payment will be charged to your Apple Account at confirmation of purchase. Subscriptions renew automatically unless canceled at least 24 hours before the end of the current period. Your account will be charged for renewal within 24 hours before the current period ends. Manage or cancel subscriptions in your App Store account settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paywallCard(reduceTransparency: reduceTransparency)
    }

    private var actionCard: some View {
        VStack(spacing: 12) {
            Button("Subscriptions Not Yet Available") { }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(store.canPurchase == false)
                .accessibilityHint("Purchases are unavailable in this version")

            Button {
                store.send(.restoreTapped)
            } label: {
                if store.isRestoring {
                    ProgressView("Restoring…")
                        .frame(maxWidth: .infinity, minHeight: 24)
                } else {
                    Text("Restore Purchases")
                        .frame(maxWidth: .infinity, minHeight: 24)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(store.isLoading || store.isRestoring)

            statusView
        }
        .frame(maxWidth: .infinity)
        .paywallCard(reduceTransparency: reduceTransparency)
    }

    @ViewBuilder private var statusView: some View {
        if let issue = store.issue {
            Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(issue == .productUnavailable ? Color.secondary : Color.orange)
                .multilineTextAlignment(.center)
            if issue == .productLoadFailed {
                Button("Try Again") { store.send(.retryTapped) }
                    .disabled(store.isLoading || store.isRestoring)
            }
        } else if store.restoreCompleted {
            switch store.entitlement {
            case .inactive:
                Text("No active subscription found.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .active:
                Text("Active subscription found. Aphrodite remains unavailable in this version.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var legalLinks: some View {
        HStack(spacing: 20) {
            Link("Privacy Policy", destination: privacyURL)
                .frame(minHeight: 44)
            Link("Terms of Use (EULA)", destination: termsURL)
                .frame(minHeight: 44)
        }
        .font(.footnote)
    }
}

private extension RemotePaywallFeature.Issue {
    var message: LocalizedStringResource {
        switch self {
        case .productUnavailable:
            "Subscription information is unavailable. Purchases remain disabled."
        case .productLoadFailed:
            "Subscription information couldn’t be loaded."
        case .restoreFailed:
            "Purchases couldn’t be restored. Please try again."
        }
    }
}

private extension View {
    @ViewBuilder
    func paywallCard(reduceTransparency: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24)
        if reduceTransparency {
            padding(20).background(Color(.secondarySystemBackground), in: shape)
        } else if #available(iOS 26, *) {
            padding(20).glassEffect(.regular, in: .rect(cornerRadius: 24))
        } else {
            padding(20).background(.regularMaterial, in: shape)
        }
    }
}
