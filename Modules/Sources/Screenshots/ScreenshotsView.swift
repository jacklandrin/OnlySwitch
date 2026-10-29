#if os(macOS)
import ComposableArchitecture
import Extensions
import SwiftUI

/// The Screenshots tab. Layout only: every interaction is a `ScreenshotsFeature` action. The same session store
/// is shown by the popover list, OnlyControl and Settings; each host keeps its own presentation state (hover,
/// which host asked for the delete-all confirmation).
public struct ScreenshotsView: View {
    @Bindable private var store: StoreOf<ScreenshotsFeature>
    private let compactPresentation: Bool
    private let resolvesFlightTarget: Bool
    /// Only the host whose button was pressed presents the shared confirmation.
    @State private var requestedDeleteAll = false

    /// - Parameter resolvesFlightTarget: whether this host reports the incoming cell's frame as the fly-in
    ///   target. The menu-bar hosts do; Settings passes false because a reveal always shows a menu-bar host.
    public init(store: StoreOf<ScreenshotsFeature>, compactPresentation: Bool = false, resolvesFlightTarget: Bool = true) {
        self.store = store
        self.compactPresentation = compactPresentation
        self.resolvesFlightTarget = resolvesFlightTarget
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: compactPresentation ? 10 : 14) {
            ScreenshotsHeader(store: store, compactPresentation: compactPresentation, deleteAll: requestDeleteAll)
            if let error = store.error {
                ScreenshotsErrorBanner(message: error.key.localized()) { store.send(.errorDismissed) }
            }
            ScreenshotsCaptureStatusCard(status: store.captureStatus, compactPresentation: compactPresentation) {
                store.send(.captureToggleChanged(true))
            }
            if store.items.isEmpty {
                if store.captureStatus != .disabled { ScreenshotsEmptyState(compactPresentation: compactPresentation) }
            } else {
                ScreenshotsGrid(store: store, compactPresentation: compactPresentation, resolvesFlightTarget: resolvesFlightTarget)
            }
        }
        .padding(compactPresentation ? 12 : 24)
        .frame(maxWidth: compactPresentation ? .infinity : 900, alignment: .leading)
        .frame(maxWidth: .infinity)
        .task { store.send(.task) }
        .confirmationDialog(
            "Delete All".localized(),
            isPresented: Binding(get: { requestedDeleteAll && store.isConfirmingDeleteAll }, set: confirmationPresentationChanged),
            titleVisibility: .visible
        ) {
            Button("Move to Trash".localized(), role: .destructive) { store.send(.deleteAllConfirmed) }
            Button("Cancel".localized(), role: .cancel) { store.send(.deleteAllCancelled) }
        } message: {
            Text("Screenshots Delete All Message".localizeWithFormat(arguments: store.deletableCount))
        }
        .onChange(of: store.isConfirmingDeleteAll) { _, isConfirming in
            if !isConfirming { requestedDeleteAll = false }
        }
    }

    private func requestDeleteAll() {
        requestedDeleteAll = true
        store.send(.deleteAllTapped)
    }

    /// A dismissal without choosing a button (Esc, click outside) cancels. The cancel is deferred one turn so a
    /// button action that SwiftUI runs after resetting the binding is still delivered first.
    private func confirmationPresentationChanged(_ isPresented: Bool) {
        guard !isPresented else { return }
        Task { @MainActor in
            requestedDeleteAll = false
            if store.isConfirmingDeleteAll { store.send(.deleteAllCancelled) }
        }
    }
}

// MARK: - Header

private struct ScreenshotsHeader: View {
    let store: StoreOf<ScreenshotsFeature>
    let compactPresentation: Bool
    let deleteAll: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label("Screenshots".localized(), systemImage: "photo.on.rectangle.angled")
                .font(compactPresentation ? .headline : .title2.bold())
                .lineLimit(1)
            if !store.items.isEmpty {
                Text(store.items.count, format: .number)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: .capsule)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 4)
            Button("Show in Finder".localized(), systemImage: "folder", action: revealFolder)
                .labelStyle(.iconOnly)
                .help("Show in Finder".localized())
            ScreenshotsDeleteAllButton(compactPresentation: compactPresentation, action: deleteAll)
                .disabled(store.deletableCount == 0)
        }
        .controlSize(compactPresentation ? .small : .regular)
    }

    private func revealFolder() { store.send(.revealFolderTapped) }
}

private struct ScreenshotsDeleteAllButton: View {
    let compactPresentation: Bool
    let action: () -> Void

    var body: some View {
        if compactPresentation {
            Button("Delete All".localized(), systemImage: "trash", action: action)
                .labelStyle(.iconOnly)
                .help("Delete All".localized())
        } else {
            Button("Delete All".localized(), systemImage: "trash", action: action)
        }
    }
}

// MARK: - Status cards

private struct ScreenshotsCaptureStatusCard: View {
    let status: ScreenshotCaptureStatus
    let compactPresentation: Bool
    let turnOn: () -> Void

    var body: some View {
        switch status {
        case .active:
            EmptyView()
        case .disabled:
            VStack(spacing: compactPresentation ? 8 : 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: compactPresentation ? 26 : 34, weight: .light))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Screenshots Capture Off Hint".localized())
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Turn On".localized(), action: turnOn)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(compactPresentation ? 14 : 22)
            .modifier(ScreenshotsSurface(cornerRadius: 14))
        case .changedElsewhere:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Screenshots Changed Elsewhere".localized())
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("Reapply".localized(), action: turnOn)
            }
            .padding(10)
            .modifier(ScreenshotsSurface(cornerRadius: 12))
            .accessibilityElement(children: .contain)
        }
    }
}

private struct ScreenshotsEmptyState: View {
    let compactPresentation: Bool

    var body: some View {
        VStack(spacing: compactPresentation ? 8 : 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: compactPresentation ? 28 : 36, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No Screenshots Yet".localized())
                .font(.headline)
            Text("Screenshots Empty Hint".localized())
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(compactPresentation ? 18 : 30)
        .modifier(ScreenshotsSurface(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

private struct ScreenshotsErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("OK".localized(), action: dismiss)
                .controlSize(.small)
        }
        .padding(10)
        .modifier(ScreenshotsSurface(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}

/// Liquid Glass on macOS 26, material with a hairline elsewhere.
private struct ScreenshotsSurface: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
                .overlay { RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.primary.opacity(0.08)) }
        }
    }
}

// MARK: - Grid

private struct ScreenshotsGrid: View {
    let store: StoreOf<ScreenshotsFeature>
    let compactPresentation: Bool
    let resolvesFlightTarget: Bool

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: compactPresentation ? 136 : 180), spacing: 10)], spacing: 10) {
            ForEach(store.items) { item in
                ScreenshotCell(
                    store: store,
                    item: item,
                    maxPixel: compactPresentation ? 480 : 640,
                    resolvesFlightTarget: resolvesFlightTarget
                )
            }
        }
    }
}

private struct ScreenshotCell: View {
    let store: StoreOf<ScreenshotsFeature>
    let item: ScreenshotItem
    let maxPixel: Int
    let resolvesFlightTarget: Bool
    @State private var thumbnail = ScreenshotThumbnailModel()
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isIncoming: Bool { store.incomingItemID == item.id }
    private var isCopied: Bool { store.copiedItemID == item.id }
    private var fileURL: URL? { store.fileURLs[item.id] }
    private var thumbnailRequest: ScreenshotThumbnailRequest { .init(url: fileURL, revision: item.revision, maxPixel: maxPixel) }
    private var pinTitle: String { (item.isPinned ? "Unpin Screenshot" : "Pin Screenshot").localized() }

    var body: some View {
        ScreenshotThumbnail(image: thumbnail.image)
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(.rect(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(isHovering ? 0.25 : 0.1)) }
            .contentShape(.rect(cornerRadius: 10))
            .gesture(TapGesture(count: 2).onEnded { open() }.exclusively(before: TapGesture().onEnded { copy() }))
            .onDrag(dragProvider) { ScreenshotThumbnail(image: thumbnail.image).frame(width: 160, height: 100).clipShape(.rect(cornerRadius: 8)) }
            .overlay(alignment: .topLeading) {
                if isHovering {
                    ScreenshotHoverButton(title: "Delete Screenshot".localized(), systemImage: "xmark", action: delete)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isHovering {
                    ScreenshotHoverButton(title: pinTitle, systemImage: item.isPinned ? "pin.fill" : "pin", action: togglePin)
                } else if item.isPinned {
                    ScreenshotPinnedBadge()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isHovering {
                    ScreenshotHoverButton(title: "Edit Screenshot".localized(), systemImage: "pencil", action: edit)
                }
            }
            .overlay {
                if isCopied { ScreenshotCopiedBadge() }
            }
            .background {
                if isIncoming && resolvesFlightTarget {
                    WindowFrameReader { frame in store.send(.flightTargetResolved(itemID: item.id, screenFrame: frame)) }
                }
            }
            .opacity(isIncoming ? 0 : 1)
            // An opacity fade is not motion: Reduce Motion skips the flight but still fades the item in.
            .animation(.easeOut(duration: 0.2), value: isIncoming)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isCopied)
            .onHover { isHovering = $0 }
            // Hiding the host (e.g. opening the editor closes the list) delivers no hover exit.
            .onDisappear { isHovering = false }
            .help(item.fileName)
            .task(id: thumbnailRequest) { await thumbnail.load(thumbnailRequest) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.fileName)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isCopied ? "Copied".localized() : "")
            .accessibilityHint("Copy".localized())
            .accessibilityAction(.default, copy)
            .accessibilityAction(named: Text("Open Screenshot".localized()), open)
            .accessibilityAction(named: Text("Edit Screenshot".localized()), edit)
            .accessibilityAction(named: Text(pinTitle), togglePin)
            .accessibilityAction(named: Text("Delete Screenshot".localized()), delete)
    }

    private func copy() { store.send(.itemTapped(item.id)) }
    private func open() { store.send(.itemDoubleTapped(item.id)) }
    private func edit() {
        // The editor closes the list without a hover exit; don't reopen it with stale hover buttons.
        isHovering = false
        store.send(.editTapped(item.id))
    }
    private func togglePin() { store.send(.pinTapped(item.id)) }
    private func delete() { store.send(.deleteTapped(item.id)) }

    /// Dragging hands other apps the recorded file; the item stays in the library.
    private func dragProvider() -> NSItemProvider {
        guard let fileURL, let provider = NSItemProvider(contentsOf: fileURL) else { return NSItemProvider() }
        provider.suggestedName = fileURL.deletingPathExtension().lastPathComponent
        return provider
    }
}

private struct ScreenshotThumbnail: View {
    let image: CGImage?

    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
            .accessibilityHidden(true)
    }
}

private struct ScreenshotHoverButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.primary)
            .frame(width: 24, height: 24)
            .modifier(ScreenshotHoverButtonSurface())
            .contentShape(.circle)
            .buttonStyle(.plain)
            .help(title)
            .padding(5)
            .transition(.opacity)
    }
}

private struct ScreenshotHoverButtonSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .background(.regularMaterial, in: .circle)
                .overlay { Circle().strokeBorder(.primary.opacity(0.12)) }
        }
    }
}

private struct ScreenshotPinnedBadge: View {
    var body: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Color.accentColor, in: .circle)
            .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
            .padding(6)
            .accessibilityHidden(true)
            .transition(.opacity)
    }
}

private struct ScreenshotCopiedBadge: View {
    var body: some View {
        Label("Copied".localized(), systemImage: "checkmark")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .modifier(ScreenshotCopiedSurface())
            .transition(.opacity)
            .accessibilityHidden(true)
    }
}

private struct ScreenshotCopiedSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.regularMaterial, in: .capsule)
        }
    }
}
#endif
