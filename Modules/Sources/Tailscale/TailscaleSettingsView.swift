#if os(macOS)
import AppKit
import ComposableArchitecture
import Extensions
import SwiftUI

public struct TailscaleSettingsView: View {
    @Bindable private var store: StoreOf<TailscaleFeature>
    public init(store: StoreOf<TailscaleFeature>) { self.store = store }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Text("Tailscale Account Notice".localized()).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let error = store.error { errorCard(error) }
                if store.mutation?.isAuthorization == true { authorizationProgress }
                if let snapshot = store.snapshot {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 0) {
                            accounts(snapshot).frame(width: 220)
                            Divider().padding(.horizontal, 20)
                            accountDetails.frame(minWidth: 270, maxWidth: .infinity)
                        }
                        VStack(alignment: .leading, spacing: 20) {
                            accounts(snapshot)
                            Divider()
                            accountDetails
                        }
                    }.padding(20).modifier(TailscaleSurface())
                    preferences(snapshot)
                } else if store.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(30)
                }
                appSettings
            }.padding(24).frame(maxWidth: 1000, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(.background)
        .onAppear { store.send(.appeared) }
        .onDisappear { store.send(.disappeared) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.send(.appeared) }
        .confirmationDialog("Tailscale Logout Confirmation".localized(), isPresented: Binding(get: { store.logoutConfirmation }, set: { if !$0 { store.send(.dismissLogout) } })) {
            Button("Tailscale Log Out".localized(), role: .destructive) { store.send(.confirmLogout) }
            Button("Tailscale Cancel".localized(), role: .cancel) { store.send(.dismissLogout) }
        }
    }

    private var header: some View {
        HStack {
            Label("Tailscale".localized(), systemImage: "network").font(.title2.bold())
            Spacer()
            if store.isBusy { ProgressView().controlSize(.small) }
            Button { store.send(.refresh) } label: { Label("Tailscale Refresh".localized(), systemImage: "arrow.clockwise") }
                .disabled(store.isBusy)
        }
    }

    private func accounts(_ snapshot: TailscaleSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tailscale Accounts".localized()).font(.headline)
            if snapshot.accounts.isEmpty {
                Text("Tailscale No Accounts".localized()).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(snapshot.accounts) { account in
                Button { store.send(.selectAccount(account.id)) } label: {
                    HStack(spacing: 10) {
                        avatar(account.title, size: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.title).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text(account.tailnet).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if account.isActive {
                                Label("Tailscale Active Account".localized(), systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(store.selectedAccountID == account.id ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 10))
                        .contentShape(.rect)
                }.buttonStyle(.plain).disabled(store.isBusy)
                    .help(account.email + " · " + account.tailnet)
                    .accessibilityAddTraits(store.selectedAccountID == account.id ? .isSelected : [])
            }
            addAccountButton.disabled(store.isBusy)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var addAccountButton: some View {
        if #available(macOS 26.0, *) {
            Button { store.send(.addAccount) } label: { Label("Tailscale Add Account".localized(), systemImage: "person.badge.plus") }.buttonStyle(.glassProminent)
        } else {
            Button { store.send(.addAccount) } label: { Label("Tailscale Add Account".localized(), systemImage: "person.badge.plus") }.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder private var accountDetails: some View {
        if let account = store.selectedAccount {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    avatar(account.title, size: 60)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(account.isActive ? store.snapshot?.connection.displayName ?? account.title : account.title).font(.title3.bold()).textSelection(.enabled)
                        if account.isActive { Text("Tailscale Active Account".localized()).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    detailRow("Tailscale Tailnet", account.tailnet)
                    detailRow("Tailscale Email", account.email)
                    if account.isActive, let connection = store.snapshot?.connection {
                        GridRow {
                            Text("Tailscale Status".localized()).foregroundStyle(.secondary)
                            Label(connection.status.localizationKey.localized(), systemImage: connection.status == .running ? "checkmark.circle.fill" : "circle")
                        }
                        GridRow {
                            Text("Tailscale Expiry".localized()).foregroundStyle(.secondary)
                            if let expiry = connection.expiry { Text(expiry, format: .dateTime.year().month().day().hour().minute()) }
                            else { Text("—") }
                        }
                    }
                }.font(.callout)
                if account.isActive {
                    Toggle("Tailscale Connection".localized(), isOn: Binding(get: { store.snapshot?.connection.status == .running }, set: { store.send(.connectChanged($0)) }))
                        .toggleStyle(.switch).disabled(store.isBusy)
                    HStack {
                        Button("Tailscale Log Out".localized(), role: .destructive) { store.send(.logout) }
                        Button("Tailscale Renew".localized()) { store.send(.renew) }
                    }.disabled(!store.canManageSelectedAccount)
                } else {
                    Button("Tailscale Switch Account".localized()) { store.send(.switchAccount) }.disabled(store.isBusy)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label("Tailscale No Accounts".localized(), systemImage: "person.crop.circle.badge.plus")
                Text("Tailscale Account Notice".localized()).font(.callout).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailRow(_ key: String, _ value: String) -> some View {
        GridRow { Text(key.localized()).foregroundStyle(.secondary); Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
    }
    private func avatar(_ name: String, size: CGFloat) -> some View {
        Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(.white).frame(width: size, height: size).background(.indigo, in: .circle).accessibilityHidden(true)
    }

    private func preferences(_ snapshot: TailscaleSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tailscale Network Settings".localized()).font(.headline)
            if !snapshot.preferencesAvailable {
                Text("Tailscale Preferences Unavailable".localized()).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(TailscalePreference.allCases, id: \.rawValue) { preference in
                    if let value = snapshot.preferences[preference] {
                        Toggle(preference.localizationKey.localized(), isOn: Binding(get: { value }, set: { store.send(.preferenceChanged(preference, $0)) }))
                            .toggleStyle(.checkbox)
                            .disabled(store.isBusy || snapshot.connection.requiresAuthentication)
                    }
                }
                Text("Tailscale Subnets Notice".localized()).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Tailscale Exit Node Notice".localized()).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Tailscale LAN Notice".localized()).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).modifier(TailscaleSurface())
    }

    private var authorizationProgress: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Tailscale Login Waiting".localized()).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Tailscale Cancel".localized()) { store.send(.cancelLogin) }
        }.padding(16).modifier(TailscaleSurface())
    }

    private func errorCard(_ error: TailscaleError) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(error.localizationKey.localized(), systemImage: "exclamationmark.triangle").fixedSize(horizontal: false, vertical: true)
            HStack {
                if error == .notInstalled { Button("Tailscale Install".localized()) { store.send(.openDownload) } }
                else { Button("Tailscale Open App".localized()) { store.send(.openApplication) } }
                if error == .authenticationRequired, store.snapshot != nil { addAccountButton.disabled(store.isBusy) }
            }
        }.font(.callout).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.08), in: .rect(cornerRadius: 12))
    }

    private var appSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tailscale Settings".localized()).font(.headline)
            Text("Tailscale App Settings Notice".localized()).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Tailscale Open App".localized()) { store.send(.openApplication) }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).modifier(TailscaleSurface())
    }
}

private struct TailscaleSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.background(.regularMaterial, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.08)))
    }
}
#endif
