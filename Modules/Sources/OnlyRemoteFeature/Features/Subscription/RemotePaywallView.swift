import ComposableArchitecture
import SwiftUI

struct RemotePaywallView: View {
    enum Presentation { case sheet, inline }

    let store: StoreOf<RemotePaywallFeature>
    var presentation: Presentation = .sheet
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let privacyURL = URL(string: "https://onlyswitch.click/#/privacy-policy")!
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        Group {
            if presentation == .sheet {
                NavigationStack {
                    content
                        .navigationTitle("OnlyRemote Plus")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Close", systemImage: "xmark") { dismiss() }
                                    .labelStyle(.iconOnly)
                                    .accessibilityHint("Closes OnlyRemote Plus")
                                    .disabled(store.isPurchasing || store.isRestoring)
                            }
                        }
                }
            } else {
                content
            }
        }
        .interactiveDismissDisabled(store.isPurchasing || store.isRestoring)
        .task { await store.send(.task).finish() }
    }

    private var content: some View {
        ZStack {
            if presentation == .sheet {
                RemotePaywallBackground()
            }
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
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
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
            Text("Aphrodite requires an active OnlyRemote Plus subscription.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var serviceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Aphrodite personal tools", systemImage: "wand.and.stars")
                .font(.title3.bold())
            Text("Sync personal tools from OnlySwitch on your Mac and use saved tools offline.")
                .foregroundStyle(.secondary)
            Label("Create tools on your Mac. Run them on your iPhone or iPad.", systemImage: "desktopcomputer.and.iphone")
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
                Text("This subscription renews automatically at \(price) per month until canceled.")
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
            Text("Payment will be charged to your Apple Account at confirmation of purchase. Subscriptions renew automatically unless canceled at least 24 hours before the end of the current period. Your account will be charged for renewal within 24 hours before the current period ends. Manage or cancel subscriptions in your App Store account settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paywallCard(reduceTransparency: reduceTransparency)
    }

    private var actionCard: some View {
        VStack(spacing: 12) {
            if store.entitlement == .inactive, store.product != nil {
                Button {
                    store.send(.purchaseTapped)
                } label: {
                    Group {
                        if store.isPurchasing {
                            ProgressView("Purchasing…")
                                .tint(.white)
                        } else if let price = store.product?.displayPrice {
                            Text("Subscribe for \(price) per month")
                        } else {
                            Text("Subscribe")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, 12)
                    .foregroundStyle(Color.white)
                    .background(Color(red: 0.05, green: 0.32, blue: 0.7), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(store.canPurchase == false)
            }

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
            .disabled(store.isBusy)

            if store.isPurchasing || store.isRestoring {
                Text("Please wait for your purchase or restoration to finish before closing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

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
            if issue == .productLoadFailed || issue == .productUnavailable {
                Button("Try Again") { store.send(.retryTapped) }
                    .disabled(store.isBusy)
            }
        } else if store.purchasePending {
            Text("Your purchase is pending approval. Access will unlock when the purchase is completed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else if store.restoreCompleted || store.entitlement != .inactive {
            switch store.entitlement {
            case .inactive:
                Text("No active subscription found.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .active:
                Text("Active subscription found. Aphrodite is ready to use.")
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

struct RemotePaywallBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        Group {
            if reduceTransparency || colorSchemeContrast == .increased {
                Color(.systemBackground)
            } else {
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.22), Color.purple.opacity(0.12), Color(.systemBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension RemotePaywallFeature.Issue {
    var message: LocalizedStringResource {
        switch self {
        case .productUnavailable:
            "Subscription information is unavailable. Please try again."
        case .productLoadFailed:
            "Subscription information couldn’t be loaded."
        case .restoreFailed:
            "Purchases couldn’t be restored. Please try again."
        case .purchaseFailed:
            "The subscription couldn’t be purchased. Please try again."
        case .verificationFailed:
            "Your purchase couldn’t be verified. Please try again."
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
