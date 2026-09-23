import ComposableArchitecture
import RemoteCore
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
        ZStack {
            DashboardBackground()

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

            if let snapshot = store.soundMixerSnapshot, snapshot.isEnabled {
                SoundMixerBottomSurface(
                    snapshot: snapshot,
                    isCollapsed: store.isSoundMixerCollapsed,
                    reduceMotion: reduceMotion,
                    collapse: { animateMixer { store.send(.soundMixerCollapsed(true)) } },
                    expand: { animateMixer { store.send(.soundMixerCollapsed(false)) } },
                    command: { store.send(.soundMixerCommand($0)) }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
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

    private func animateMixer(_ action: () -> Void) {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.18)) { action() }
        } else {
            withAnimation(.snappy(duration: 0.42, extraBounce: 0.08)) { action() }
        }
    }
}

private struct SoundMixerBottomSurface: View {
    let snapshot: RemoteSoundMixerSnapshot
    let isCollapsed: Bool
    let reduceMotion: Bool
    let collapse: () -> Void
    let expand: () -> Void
    let command: (RemoteSoundMixerCommand) -> Void

    var body: some View {
        Group {
            if isCollapsed {
                Button("Expand Sound Mixer", systemImage: "speaker.wave.2.fill", action: expand)
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: 300)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .modifier(SoundMixerGlass(shape: .capsule, interactive: true))
                    .transition(surfaceTransition)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Capsule().fill(.secondary).frame(width: 36, height: 5).frame(maxWidth: .infinity)
                    HStack {
                        Label("Sound Mixer", systemImage: "slider.horizontal.3")
                            .font(.headline)
                        Spacer()
                        Button("Collapse Sound Mixer", systemImage: "chevron.down", action: collapse)
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("Collapse Sound Mixer")
                    }
                    if let output = snapshot.output {
                        Label(output.name, systemImage: output.symbolName)
                            .foregroundStyle(.secondary)
                    }
                    SoundMixerSlider(label: "System Volume", value: snapshot.systemVolume) {
                        command(.setSystemVolume($0))
                    }
                    if snapshot.apps.isEmpty {
                        ContentUnavailableView("No controllable apps are running", systemImage: "speaker.slash")
                    } else {
                        ScrollView {
                            VStack(spacing: 14) {
                                ForEach(snapshot.apps) { app in
                                    HStack {
                                        SoundMixerSlider(label: app.name, value: app.volume) {
                                            command(.setAppVolume(id: app.id, volume: $0))
                                        }
                                        Button(app.isMuted ? "Unmute \(app.name)" : "Mute \(app.name)", systemImage: app.isMuted ? "speaker.slash.fill" : "speaker.fill") {
                                            command(.setAppMuted(id: app.id, isMuted: !app.isMuted))
                                        }
                                        .labelStyle(.iconOnly)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxHeight: 380)
                .modifier(SoundMixerGlass(shape: .rect(cornerRadius: 30), interactive: false))
                .gesture(DragGesture().onEnded { if $0.translation.height > 80 { collapse() } })
                .transition(surfaceTransition)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: isCollapsed)
    }

    private var surfaceTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .scale(scale: 0.82, anchor: .bottom).combined(with: .opacity),
            removal: .scale(scale: 0.82, anchor: .bottom).combined(with: .opacity)
        )
    }
}

private struct SoundMixerSlider: View {
    let label: String
    let value: Double
    let changed: (Double) -> Void
    @State private var localValue: Double
    @State private var isEditing = false
    @State private var debounceTask: Task<Void, Never>?

    init(label: String, value: Double, changed: @escaping (Double) -> Void) {
        self.label = label
        self.value = value
        self.changed = changed
        _localValue = State(initialValue: value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline)
            Slider(value: $localValue, in: 0...100, onEditingChanged: editingChanged)
                .accessibilityLabel(label)
                .accessibilityValue("\(Int(localValue.rounded()))%")
        }
        .onChange(of: value) { _, newValue in
            if isEditing == false { localValue = newValue }
        }
        .onChange(of: localValue) { _, newValue in
            guard isEditing else { return }
            scheduleDebouncedChange(newValue)
        }
        .onDisappear { debounceTask?.cancel() }
    }

    private func editingChanged(_ editing: Bool) {
        isEditing = editing
        guard editing == false else { return }
        debounceTask?.cancel()
        debounceTask = nil
        changed(localValue)
    }

    private func scheduleDebouncedChange(_ newValue: Double) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(120))
                guard Task.isCancelled == false else { return }
                changed(newValue)
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }
}

private struct SoundMixerGlass<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    let interactive: Bool
    func body(content: Content) -> some View {
        if reduceTransparency { content.background(Color.primary.opacity(0.12), in: shape) }
        else if #available(iOS 26, *) { content.glassEffect(.regular.interactive(interactive), in: shape) }
        else { content.background(.thinMaterial, in: shape) }
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
