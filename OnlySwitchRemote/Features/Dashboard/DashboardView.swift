import ComposableArchitecture
import SwiftUI

struct DashboardView: View {
    @Bindable var store: StoreOf<DashboardFeature>
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                MacPickerView(
                    macs: Array(store.pairedMacs),
                    selectedMacID: store.selectedMacID,
                    select: { store.send(.macSelected($0)) }
                )
                .frame(maxWidth: 280)

                if let connectionMessage {
                    Label(connectionMessage, systemImage: connectionSymbol)
                        .font(.subheadline)
                        .foregroundStyle(connectionColor)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal)
                        .accessibilityLabel(connectionMessage)
                }

                if store.selectedMacID == nil {
                    ContentUnavailableView(
                        "No Mac Selected",
                        systemImage: "desktopcomputer",
                        description: Text("Open Settings to pair with a Mac running OnlySwitch.")
                    )
                    .frame(minHeight: 260)
                } else if store.visibleDescriptors.isEmpty {
                    ContentUnavailableView(
                        "No Dashboard Tiles",
                        systemImage: "square.grid.2x2",
                        description: Text("Choose controls in Settings to add them here.")
                    )
                    .frame(minHeight: 260)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(store.visibleDescriptors) { descriptor in
                            ControlTileView(
                                descriptor: descriptor,
                                status: store.statuses[descriptor.id],
                                macName: store.selectedMac?.displayName ?? String(localized: "Mac"),
                                isRequestInFlight: store.requestsInFlight.contains(descriptor.id),
                                isEnabled: store.actionableControlIDs.contains(descriptor.id),
                                reduceMotion: reduceMotion,
                                action: { store.send(.tileTapped(descriptor.id)) }
                            )
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("OnlySwitch")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "line.3.horizontal") {
                    store.send(.menuTapped)
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("Settings")
                .accessibilityHint("Opens remote control settings")
            }
        }
        .task { await store.send(.task).finish() }
        .alert($store.scope(state: \.alert, action: \.alert))
    }

    private var columns: [GridItem] {
        if horizontalSizeClass == .compact {
            return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        }
        return [GridItem(.adaptive(minimum: 160), spacing: 12)]
    }

    private var connectionMessage: String? {
        switch store.connectionState {
        case .idle: nil
        case .connecting: String(localized: "Connecting…")
        case .authenticated: nil
        case let .offline(reason): reason ?? String(localized: "Mac Offline — controls are disabled")
        case .revoked: String(localized: "Pairing required — open Settings to reconnect")
        }
    }

    private var connectionSymbol: String {
        switch store.connectionState {
        case .connecting: "arrow.triangle.2.circlepath"
        case .revoked: "key.slash"
        default: "wifi.slash"
        }
    }

    private var connectionColor: Color {
        store.connectionState == .connecting ? .secondary : .orange
    }
}
