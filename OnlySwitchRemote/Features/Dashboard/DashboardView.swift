import ComposableArchitecture
import SwiftUI

struct DashboardView: View {
    @Bindable var store: StoreOf<DashboardFeature>
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum GridStrategy: Equatable {
        case fixed(count: Int)
        case adaptive(minimum: CGFloat)

        var columns: [GridItem] {
            switch self {
            case let .fixed(count):
                Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
            case let .adaptive(minimum):
                [GridItem(.adaptive(minimum: minimum), spacing: 12)]
            }
        }
    }

    static func gridStrategy(
        horizontal: UserInterfaceSizeClass?,
        vertical: UserInterfaceSizeClass?
    ) -> GridStrategy {
        if vertical == .compact { return .adaptive(minimum: 180) }
        if horizontal == .compact { return .fixed(count: 2) }
        return .adaptive(minimum: 160)
    }

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
        Self.gridStrategy(
            horizontal: horizontalSizeClass,
            vertical: verticalSizeClass
        ).columns
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
