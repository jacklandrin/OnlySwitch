#if os(macOS)
import ComposableArchitecture
import Extensions
import SwiftUI

/// Editor window content: toolbar on top, fitted canvas below. Layout only; every edit is a reducer action and
/// drag locations are converted to image pixel space before they are sent.
public struct ScreenshotEditorView: View {
    let store: StoreOf<ScreenshotEditorFeature>
    public init(store: StoreOf<ScreenshotEditorFeature>) { self.store = store }

    public var body: some View {
        VStack(spacing: 12) {
            ScreenshotEditorToolbar(store: store)
            if let error = store.error {
                ScreenshotEditorErrorBanner(message: error.key.localized(), dismiss: dismissError)
            }
            ScreenshotEditorCanvas(store: store)
        }
        .padding(12)
        .frame(minWidth: 520, minHeight: 380)
        .background(.background)
        .task { store.send(.task) }
    }

    private func dismissError() { store.send(.errorDismissed) }
}

// MARK: - Toolbar

private struct ScreenshotEditorToolbar: View {
    let store: StoreOf<ScreenshotEditorFeature>

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                ScreenshotToolPicker(store: store)
                Divider().frame(height: 22)
                ScreenshotStylePicker(store: store)
                Divider().frame(height: 22)
                ScreenshotHistoryButtons(store: store)
                Spacer(minLength: 8)
                ScreenshotCommitButtons(store: store)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ScreenshotToolPicker(store: store)
                    Spacer(minLength: 8)
                    ScreenshotHistoryButtons(store: store)
                }
                HStack(spacing: 10) {
                    ScreenshotStylePicker(store: store)
                    Spacer(minLength: 8)
                    ScreenshotCommitButtons(store: store)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .modifier(ScreenshotEditorSurface())
    }
}

private extension ScreenshotTool {
    var title: String {
        switch self {
        case .pen: "Pen".localized()
        case .rectangle: "Rectangle".localized()
        case .ellipse: "Ellipse".localized()
        case .arrow: "Arrow".localized()
        case .blur: "Blur".localized()
        case .crop: "Crop".localized()
        }
    }
    var symbol: String {
        switch self {
        case .pen: "pencil.tip"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .arrow: "arrow.up.right"
        case .blur: "drop.halffull"
        case .crop: "crop"
        }
    }
}

private struct ScreenshotToolPicker: View {
    let store: StoreOf<ScreenshotEditorFeature>

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ScreenshotTool.allCases, id: \.self) { tool in
                ScreenshotToolButton(tool: tool, isSelected: store.tool == tool) { store.send(.toolSelected(tool)) }
            }
        }
        .padding(2)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }
}

private struct ScreenshotToolButton: View {
    let tool: ScreenshotTool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(tool.title, systemImage: tool.symbol)
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 24)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? Color.accentColor : Color.clear, in: .rect(cornerRadius: 6))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(tool.title)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ScreenshotStylePicker: View {
    let store: StoreOf<ScreenshotEditorFeature>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(RGBAColor.palette.enumerated()), id: \.element) { index, color in
                ScreenshotColorSwatch(color: color, index: index, isSelected: store.style.color == color) { store.send(.colorSelected(color)) }
            }
            Divider().frame(height: 22)
            ForEach(AnnotationStyle.lineWidths, id: \.self) { width in
                ScreenshotLineWidthButton(width: width, isSelected: store.style.lineWidth == width) { store.send(.lineWidthSelected(width)) }
            }
        }
        .disabled(store.tool == .blur || store.tool == .crop)
    }
}

private struct ScreenshotColorSwatch: View {
    let color: RGBAColor
    let index: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(cgColor: color.cgColor))
                .overlay { Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1) }
                .overlay {
                    // Selection is shown by a ring and a checkmark, not by color alone.
                    if isSelected {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 2).padding(-3)
                        Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(color == .white ? Color.black : Color.white)
                    }
                }
                .frame(width: 18, height: 18)
                .padding(3)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Color".localized())
        .accessibilityLabel("Color".localized())
        .accessibilityValue("\(index + 1)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ScreenshotLineWidthButton: View {
    let width: CGFloat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Capsule()
                .frame(width: 16, height: min(width / 1.5, 8))
                .frame(width: 26, height: 24)
                .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear, in: .rect(cornerRadius: 6))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Line Width".localized())
        .accessibilityLabel("Line Width".localized())
        .accessibilityValue("\(Int(width))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ScreenshotHistoryButtons: View {
    let store: StoreOf<ScreenshotEditorFeature>

    var body: some View {
        HStack(spacing: 4) {
            Button("Undo".localized(), systemImage: "arrow.uturn.backward", action: undo)
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!store.canUndo)
                .help("Undo".localized())
            Button("Redo".localized(), systemImage: "arrow.uturn.forward", action: redo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!store.canRedo)
                .help("Redo".localized())
            Button("Reset Crop".localized(), systemImage: "arrow.counterclockwise", action: resetCrop)
                .disabled(store.document.crop == nil)
                .help("Reset Crop".localized())
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .disabled(store.isSaving)
    }

    private func undo() { store.send(.undo) }
    private func redo() { store.send(.redo) }
    private func resetCrop() { store.send(.resetCrop) }
}

private struct ScreenshotCommitButtons: View {
    let store: StoreOf<ScreenshotEditorFeature>

    var body: some View {
        HStack(spacing: 8) {
            Button("Cancel".localized(), action: cancel)
                .keyboardShortcut(.cancelAction)
                .disabled(store.isSaving)
            Button(action: save) {
                if store.isSaving { ProgressView().controlSize(.small) } else { Text("Save".localized()) }
            }
            .keyboardShortcut("s", modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(!store.canSave)
            .accessibilityLabel("Save".localized())
            .help("Save".localized())
        }
    }

    private func cancel() { store.send(.cancelTapped) }
    private func save() { store.send(.saveTapped) }
}

private struct ScreenshotEditorErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
            Text(message).font(.callout)
            Spacer(minLength: 8)
            Button("OK".localized(), action: dismiss).controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .modifier(ScreenshotEditorSurface())
        .accessibilityElement(children: .combine)
    }
}

private struct ScreenshotEditorSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 14))
        } else {
            content
                .background(.regularMaterial, in: .rect(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.08)) }
        }
    }
}

// MARK: - Canvas

private struct ScreenshotEditorCanvas: View {
    let store: StoreOf<ScreenshotEditorFeature>

    var body: some View {
        GeometryReader { proxy in
            let geometry = ScreenshotCanvasGeometry(pixelSize: store.document.pixelSize, container: proxy.size)
            ZStack(alignment: .topLeading) {
                if let image = store.image {
                    Image(decorative: image.cgImage, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: geometry.fitted.width, height: geometry.fitted.height)
                        .offset(x: geometry.fitted.minX, y: geometry.fitted.minY)
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    ScreenshotAnnotationOverlay(
                        geometry: geometry,
                        blurredImage: image.blurredImage,
                        annotations: store.document.annotations + (store.draft.map { [$0] } ?? []),
                        crop: store.draftCrop ?? store.document.crop
                    )
                    .allowsHitTesting(false)
                } else if store.error == nil {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .contentShape(.rect)
            .gesture(dragGesture(geometry))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Edit Screenshot".localized())
    }

    private func dragGesture(_ geometry: ScreenshotCanvasGeometry) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                store.send(.dragChanged(start: geometry.pixelPoint(value.startLocation), current: geometry.pixelPoint(value.location)))
            }
            .onEnded { _ in store.send(.dragEnded) }
    }
}

/// Aspect-fit placement of the image (never upscaled past one point per pixel) and view ↔ pixel conversion.
private struct ScreenshotCanvasGeometry {
    let fitted: CGRect
    let scale: CGFloat

    init(pixelSize: CGSize, container: CGSize) {
        guard pixelSize.width > 0, pixelSize.height > 0, container.width > 0, container.height > 0 else {
            fitted = .zero; scale = 1; return
        }
        let scale = min(1, container.width / pixelSize.width, container.height / pixelSize.height)
        let size = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
        self.scale = scale
        fitted = CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2, width: size.width, height: size.height)
    }

    func pixelPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - fitted.minX) / scale, y: (point.y - fitted.minY) / scale)
    }
}

/// Blur patches use the cached renderer image; vectors are drawn afterward, matching saved output order.
/// Crop remains a dimmed outside region so the source coordinates stay stable while editing.
private struct ScreenshotAnnotationOverlay: View {
    let geometry: ScreenshotCanvasGeometry
    let blurredImage: CGImage?
    let annotations: [ScreenshotAnnotation]
    let crop: CGRect?

    var body: some View {
        Canvas { context, size in
            let transform = CGAffineTransform(translationX: geometry.fitted.minX, y: geometry.fitted.minY).scaledBy(x: geometry.scale, y: geometry.scale)
            var blurMask = Path()
            for annotation in annotations {
                if case let .blur(rect) = annotation {
                    let region = rect.standardized.applying(transform).intersection(geometry.fitted)
                    if !region.isEmpty { blurMask.addRect(region) }
                }
            }
            var blurredContext = context
            blurredContext.clip(to: blurMask)
            if let blurredImage {
                blurredContext.draw(Image(decorative: blurredImage, scale: 1), in: geometry.fitted)
            } else {
                // A failed preview must not leave the selected source text visible.
                blurredContext.fill(Path(geometry.fitted), with: .color(.gray))
            }
            for annotation in annotations {
                if case .blur = annotation { continue }
                context.withCGContext { cg in
                    cg.concatenate(transform)
                    ScreenshotRenderer.draw(annotation, in: cg)
                }
            }
            if let crop { drawCrop(crop.standardized.applying(transform), size: size, in: &context) }
        }
    }

    private func drawCrop(_ rect: CGRect, size: CGSize, in context: inout GraphicsContext) {
        var outside = Path(geometry.fitted)
        outside.addRect(rect)
        context.fill(outside, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
        context.stroke(Path(rect), with: .color(.white), lineWidth: 1.5)
        let handle: CGFloat = 8
        for corner in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)] {
            let square = CGRect(x: corner.x - handle / 2, y: corner.y - handle / 2, width: handle, height: handle)
            context.fill(Path(square), with: .color(.white))
            context.stroke(Path(square), with: .color(.black.opacity(0.35)), lineWidth: 0.5)
        }
    }
}
#endif
