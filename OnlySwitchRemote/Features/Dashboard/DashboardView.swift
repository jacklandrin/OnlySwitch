import ComposableArchitecture
import SwiftUI

struct DashboardView: View {
    @Bindable var store: StoreOf<DashboardFeature>
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    enum GridStrategy: Equatable {
        case fixed(count: Int)
        case adaptive(minimum: CGFloat)

        var columns: [GridItem] {
            switch self {
            case let .fixed(count):
                Array(repeating: GridItem(.flexible(), spacing: 16), count: count)
            case let .adaptive(minimum):
                [GridItem(.adaptive(minimum: minimum), spacing: 16)]
            }
        }
    }

    static func gridStrategy(
        horizontal: UserInterfaceSizeClass?,
        vertical: UserInterfaceSizeClass?,
        dynamicTypeSize: DynamicTypeSize
    ) -> GridStrategy {
        if dynamicTypeSize.isAccessibilitySize { return .fixed(count: 1) }
        if vertical == .compact { return .adaptive(minimum: 220) }
        if horizontal == .compact { return .fixed(count: 2) }
        return .adaptive(minimum: 240)
    }

    var body: some View {
        ScrollView {
            DashboardGlassContainer(spacing: 16) {
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
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background {
                                if reduceTransparency {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(opaqueSurfaceColor)
                                } else {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(.thinMaterial)
                                }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(
                                        Color.primary.opacity(colorSchemeContrast == .increased ? 0.42 : 0.10),
                                        lineWidth: colorSchemeContrast == .increased ? 2 : 1
                                    )
                            }
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
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(store.visibleDescriptors) { descriptor in
                                let presentation = ControlTilePresentation(
                                    descriptor: descriptor,
                                    status: store.statuses[descriptor.id],
                                    connectionState: store.connectionState,
                                    isRequestInFlight: store.requestsInFlight.contains(descriptor.id),
                                    actionFailure: store.actionFailures[descriptor.id]
                                )
                                ControlTileView(
                                    descriptor: descriptor,
                                    presentation: presentation,
                                    macName: store.selectedMac?.displayName ?? String(localized: "Mac"),
                                    isEnabled: store.actionableControlIDs.contains(descriptor.id),
                                    reduceMotion: reduceMotion,
                                    action: { store.send(.tileTapped(descriptor.id)) }
                                )
                            }
                        }
                    }
                }
            }
            .padding(20)
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
            vertical: verticalSizeClass,
            dynamicTypeSize: dynamicTypeSize
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

    private var opaqueSurfaceColor: Color {
        colorScheme == .dark
            ? Color(red: 0.12, green: 0.12, blue: 0.13)
            : .white
    }
}

private struct DashboardGlassContainer<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26, *), reduceTransparency == false {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}
