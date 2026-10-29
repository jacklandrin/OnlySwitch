#if os(macOS)
import ComposableArchitecture
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// The decoded source image of an editor session. `CGImage` is immutable but not annotated `Sendable`, so it
/// travels in this box. Equality is by file, pixel size and type (not pixels): an editor session loads one file once.
public final class ScreenshotEditorImage: Equatable, @unchecked Sendable {
    public let cgImage: CGImage
    public let fileURL: URL
    /// Encoding type for Save: the original file's type.
    public let type: UTType
    public init(cgImage: CGImage, fileURL: URL, type: UTType) { self.cgImage = cgImage; self.fileURL = fileURL; self.type = type }
    public var pixelSize: CGSize { CGSize(width: cgImage.width, height: cgImage.height) }
    public static func == (lhs: ScreenshotEditorImage, rhs: ScreenshotEditorImage) -> Bool {
        lhs === rhs || (lhs.fileURL == rhs.fileURL && lhs.pixelSize == rhs.pixelSize && lhs.type == rhs.type)
    }
}

/// One annotation session for a recorded screenshot: tools, drag gestures (already in pixel space), undo/redo,
/// crop and save. The original file is only overwritten on Save, through `client.replaceImage`.
@Reducer
public struct ScreenshotEditorFeature {
    @ObservableState
    public struct State: Equatable {
        public let itemID: UUID
        /// `pixelSize` is zero until the image is loaded.
        public var document: ScreenshotEditDocument
        public var image: ScreenshotEditorImage?
        public var isLoading = false
        public var tool: ScreenshotTool = .pen
        public var style = AnnotationStyle()
        public var draft: ScreenshotAnnotation?
        /// Live crop rectangle while dragging with the crop tool (clipped to the image, not yet clamped).
        public var draftCrop: CGRect?
        public var undoStack: [ScreenshotEditDocument] = []
        public var redoStack: [ScreenshotEditDocument] = []
        public var isSaving = false
        public var error: ScreenshotFailure?

        public init(itemID: UUID, document: ScreenshotEditDocument = .init(pixelSize: .zero)) { self.itemID = itemID; self.document = document }
        public var isLoaded: Bool { document.pixelSize.width > 0 && document.pixelSize.height > 0 }
        public var canUndo: Bool { !undoStack.isEmpty }
        public var canRedo: Bool { !redoStack.isEmpty }
        public var canSave: Bool { image != nil && !isSaving }
    }

    public enum Action: Equatable, Sendable {
        case task
        case imageLoaded(Result<ScreenshotEditorImage, ScreenshotFailure>)
        case toolSelected(ScreenshotTool)
        case colorSelected(RGBAColor)
        case lineWidthSelected(CGFloat)
        case dragChanged(start: CGPoint, current: CGPoint)
        case dragEnded
        case undo
        case redo
        case resetCrop
        case saveTapped
        case saveResponse(Result<[ScreenshotItem], ScreenshotFailure>)
        case cancelTapped
        case errorDismissed
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable { case finished(updatedItems: [ScreenshotItem]?) }
    }

    @Dependency(\.screenshotsClient) var client
    static let minimumDraftSide: CGFloat = 2
    static let undoLimit = 100

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                guard state.image == nil, !state.isLoading else { return .none }
                state.isLoading = true
                let id = state.itemID
                return .run { [client] send in
                    guard let url = await client.fileURL(id), let image = ScreenshotRenderer.loadImage(at: url) else {
                        await send(.imageLoaded(.failure(ScreenshotFailure(key: ScreenshotFailure.notFoundKey, itemID: id)))); return
                    }
                    await send(.imageLoaded(.success(ScreenshotEditorImage(cgImage: image, fileURL: url, type: ScreenshotRenderer.outputType(for: url)))))
                }
            case let .imageLoaded(.success(image)):
                state.isLoading = false
                state.image = image
                state.document.pixelSize = image.pixelSize
                return .none
            case let .imageLoaded(.failure(failure)):
                state.isLoading = false
                state.error = failure
                return .none

            case let .toolSelected(tool):
                state.tool = tool; state.draft = nil; state.draftCrop = nil
                return .none
            case let .colorSelected(color):
                state.style.color = color
                return .none
            case let .lineWidthSelected(width):
                state.style.lineWidth = width
                return .none

            case let .dragChanged(start, current):
                guard state.isLoaded, !state.isSaving else { return .none }
                updateDraft(&state, start: clamp(start, state), current: clamp(current, state))
                return .none
            case .dragEnded:
                commitDraft(&state)
                return .none

            case .undo:
                guard let previous = state.undoStack.popLast() else { return .none }
                state.redoStack.append(state.document)
                state.document = previous
                return .none
            case .redo:
                guard let next = state.redoStack.popLast() else { return .none }
                state.undoStack.append(state.document)
                state.document = next
                return .none
            case .resetCrop:
                guard state.document.crop != nil else { return .none }
                var document = state.document
                document.crop = nil
                commit(document, &state)
                return .none

            case .saveTapped:
                guard let image = state.image, !state.isSaving else { return .none }
                state.isSaving = true; state.error = nil
                let id = state.itemID, document = state.document
                return .run { [client] send in
                    let failure = ScreenshotFailure(key: ScreenshotFailure.saveFailedKey, itemID: id)
                    guard let rendered = ScreenshotRenderer.render(image.cgImage, document: document),
                          let data = ScreenshotRenderer.encode(rendered, as: image.type) else {
                        await send(.saveResponse(.failure(failure))); return
                    }
                    do { await send(.saveResponse(.success(try await client.replaceImage(id, data)))) }
                    catch { await send(.saveResponse(.failure(failure))) }
                }
            case let .saveResponse(.success(items)):
                state.isSaving = false
                return .send(.delegate(.finished(updatedItems: items)))
            case let .saveResponse(.failure(failure)):
                state.isSaving = false
                state.error = failure
                return .none

            case .cancelTapped:
                guard !state.isSaving else { return .none }
                return .send(.delegate(.finished(updatedItems: nil)))
            case .errorDismissed:
                state.error = nil
                return .none
            case .delegate:
                return .none
            }
        }
    }

    private func clamp(_ point: CGPoint, _ state: State) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), state.document.pixelSize.width), y: min(max(point.y, 0), state.document.pixelSize.height))
    }

    private func updateDraft(_ state: inout State, start: CGPoint, current: CGPoint) {
        let rect = CGRect(x: start.x, y: start.y, width: current.x - start.x, height: current.y - start.y).standardized
        switch state.tool {
        case .pen:
            if case .stroke(var points, let style) = state.draft {
                if points.last != current { points.append(current) }
                state.draft = .stroke(points, style)
            } else {
                state.draft = .stroke([start, current], state.style)
            }
        case .rectangle: state.draft = .rectangle(rect, state.style)
        case .ellipse: state.draft = .ellipse(rect, state.style)
        case .arrow: state.draft = .arrow(from: start, to: current, state.style)
        case .blur: state.draft = .blur(rect)
        case .crop: state.draftCrop = rect
        }
    }

    /// Commits the draft as one undo step; drafts smaller than 2px are discarded.
    private func commitDraft(_ state: inout State) {
        let draft = state.draft, draftCrop = state.draftCrop
        state.draft = nil; state.draftCrop = nil
        let minimum = Self.minimumDraftSide
        func isLarge(_ rect: CGRect) -> Bool { rect.width >= minimum && rect.height >= minimum }
        var document = state.document
        if let draftCrop {
            guard isLarge(draftCrop), let crop = document.clampedCrop(draftCrop) else { return }
            document.crop = crop
        } else if let draft {
            switch draft {
            case let .stroke(points, _):
                let xs = points.map(\.x), ys = points.map(\.y)
                guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(),
                      max(maxX - minX, maxY - minY) >= minimum else { return }
                document.annotations.append(draft)
            case let .rectangle(rect, _), let .ellipse(rect, _):
                guard isLarge(rect) else { return }
                document.annotations.append(draft)
            case let .arrow(from, to, _):
                guard hypot(to.x - from.x, to.y - from.y) >= minimum else { return }
                document.annotations.append(draft)
            case let .blur(rect):
                guard isLarge(rect), let region = document.clampedRegion(rect) else { return }
                document.annotations.append(.blur(region))
            }
        } else {
            return
        }
        commit(document, &state)
    }

    private func commit(_ document: ScreenshotEditDocument, _ state: inout State) {
        guard document != state.document else { return }
        state.undoStack.append(state.document)
        if state.undoStack.count > Self.undoLimit { state.undoStack.removeFirst(state.undoStack.count - Self.undoLimit) }
        state.redoStack.removeAll()
        state.document = document
    }
}
#endif
