#if os(macOS)
import ComposableArchitecture
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Screenshots

@MainActor
struct ScreenshotEditorFeatureTests {
    let itemID = UUID()
    let size = CGSize(width: 100, height: 80)
    let style = AnnotationStyle()

    func loaded(tool: ScreenshotTool = .rectangle) -> ScreenshotEditorFeature.State {
        var state = ScreenshotEditorFeature.State(itemID: itemID)
        state.document.pixelSize = size
        state.tool = tool
        return state
    }

    func makeStore(_ state: ScreenshotEditorFeature.State, client: ScreenshotsClient = .testValue) -> TestStoreOf<ScreenshotEditorFeature> {
        TestStore(initialState: state) { ScreenshotEditorFeature() } withDependencies: { $0.screenshotsClient = client }
    }

    @Test func dragCreatesDraftAndEndCommitsWithUndo() async {
        let store = makeStore(loaded())
        let rect = CGRect(x: 10, y: 10, width: 30, height: 20)
        // Dragging up-left still yields a standardized rectangle.
        await store.send(.dragChanged(start: CGPoint(x: 40, y: 30), current: CGPoint(x: 10, y: 10))) {
            $0.draft = .rectangle(rect, self.style)
        }
        await store.send(.dragEnded) {
            $0.draft = nil
            $0.undoStack = [ScreenshotEditDocument(pixelSize: self.size)]
            $0.document.annotations = [.rectangle(rect, self.style)]
        }

        await store.send(.toolSelected(.pen)) { $0.tool = .pen }
        await store.send(.dragChanged(start: CGPoint(x: 1, y: 1), current: CGPoint(x: 5, y: 5))) {
            $0.draft = .stroke([CGPoint(x: 1, y: 1), CGPoint(x: 5, y: 5)], self.style)
        }
        await store.send(.dragChanged(start: CGPoint(x: 1, y: 1), current: CGPoint(x: 9, y: 4))) {
            $0.draft = .stroke([CGPoint(x: 1, y: 1), CGPoint(x: 5, y: 5), CGPoint(x: 9, y: 4)], self.style)
        }
        // Points outside the image are clamped to its bounds.
        await store.send(.dragChanged(start: CGPoint(x: 1, y: 1), current: CGPoint(x: 140, y: -20))) {
            $0.draft = .stroke([CGPoint(x: 1, y: 1), CGPoint(x: 5, y: 5), CGPoint(x: 9, y: 4), CGPoint(x: 100, y: 0)], self.style)
        }
        await store.send(.dragEnded) {
            $0.draft = nil
            $0.undoStack.append($0.document)
            $0.document.annotations.append(.stroke([CGPoint(x: 1, y: 1), CGPoint(x: 5, y: 5), CGPoint(x: 9, y: 4), CGPoint(x: 100, y: 0)], self.style))
        }

        let green = AnnotationStyle(color: .green, lineWidth: 12)
        await store.send(.colorSelected(.green)) { $0.style.color = .green }
        await store.send(.lineWidthSelected(12)) { $0.style.lineWidth = 12 }
        await store.send(.toolSelected(.arrow)) { $0.tool = .arrow }
        await store.send(.dragChanged(start: CGPoint(x: 50, y: 50), current: CGPoint(x: 70, y: 60))) {
            $0.draft = .arrow(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 70, y: 60), green)
        }
        await store.send(.dragEnded) {
            $0.draft = nil
            $0.undoStack.append($0.document)
            $0.document.annotations.append(.arrow(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 70, y: 60), green))
        }
    }

    @Test func tinyDragIsDiscarded() async {
        let store = makeStore(loaded(tool: .ellipse))
        await store.send(.dragChanged(start: CGPoint(x: 10, y: 10), current: CGPoint(x: 11, y: 30))) {
            $0.draft = .ellipse(CGRect(x: 10, y: 10, width: 1, height: 20), self.style)
        }
        await store.send(.dragEnded) { $0.draft = nil }
        await store.send(.toolSelected(.arrow)) { $0.tool = .arrow }
        await store.send(.dragChanged(start: CGPoint(x: 10, y: 10), current: CGPoint(x: 11, y: 11))) {
            $0.draft = .arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 11, y: 11), self.style)
        }
        await store.send(.dragEnded) { $0.draft = nil }
        await store.send(.toolSelected(.crop)) { $0.tool = .crop }
        await store.send(.dragChanged(start: CGPoint(x: 10, y: 10), current: CGPoint(x: 11, y: 11))) {
            $0.draftCrop = CGRect(x: 10, y: 10, width: 1, height: 1)
        }
        await store.send(.dragEnded) { $0.draftCrop = nil }
        // Without a loaded image nothing can be drawn.
        let unloaded = makeStore(.init(itemID: itemID))
        await unloaded.send(.dragChanged(start: .zero, current: CGPoint(x: 50, y: 50)))
        await unloaded.send(.dragEnded)
    }

    @Test func undoRedoRestoresDocuments() async {
        let first = ScreenshotAnnotation.blur(CGRect(x: 0, y: 0, width: 10, height: 10))
        let second = ScreenshotAnnotation.blur(CGRect(x: 20, y: 20, width: 10, height: 10))
        let store = makeStore(loaded(tool: .blur))
        await store.send(.dragChanged(start: .zero, current: CGPoint(x: 10, y: 10))) { $0.draft = first }
        await store.send(.dragEnded) { $0.draft = nil; $0.undoStack = [ScreenshotEditDocument(pixelSize: self.size)]; $0.document.annotations = [first] }
        await store.send(.dragChanged(start: CGPoint(x: 20, y: 20), current: CGPoint(x: 30, y: 30))) { $0.draft = second }
        await store.send(.dragEnded) { $0.draft = nil; $0.undoStack.append($0.document); $0.document.annotations = [first, second] }

        await store.send(.undo) {
            $0.redoStack = [$0.document]; $0.document = $0.undoStack.removeLast()
        }
        #expect(store.state.document.annotations == [first])
        await store.send(.undo) {
            $0.redoStack.append($0.document); $0.document = $0.undoStack.removeLast()
        }
        #expect(store.state.document.annotations.isEmpty)
        await store.send(.undo)
        await store.send(.redo) {
            $0.undoStack.append($0.document); $0.document = $0.redoStack.removeLast()
        }
        await store.send(.redo) {
            $0.undoStack.append($0.document); $0.document = $0.redoStack.removeLast()
        }
        #expect(store.state.document.annotations == [first, second])
        await store.send(.redo)
    }

    @Test func newEditClearsRedoStack() async {
        let first = ScreenshotAnnotation.rectangle(CGRect(x: 0, y: 0, width: 10, height: 10), style)
        var state = loaded()
        state.document.annotations = [first]
        state.undoStack = [ScreenshotEditDocument(pixelSize: size)]
        let store = makeStore(state)
        await store.send(.undo) { $0.redoStack = [$0.document]; $0.document = $0.undoStack.removeLast() }
        await store.send(.dragChanged(start: CGPoint(x: 30, y: 30), current: CGPoint(x: 40, y: 40))) {
            $0.draft = .rectangle(CGRect(x: 30, y: 30, width: 10, height: 10), self.style)
        }
        await store.send(.dragEnded) {
            $0.draft = nil
            $0.undoStack = [$0.document]
            $0.redoStack = []
            $0.document.annotations = [.rectangle(CGRect(x: 30, y: 30, width: 10, height: 10), self.style)]
        }
    }

    @Test func cropIsClampedToImageAndMinimumSize() async {
        let store = makeStore(loaded(tool: .crop))
        await store.send(.dragChanged(start: CGPoint(x: 60, y: 50), current: CGPoint(x: 130, y: 120))) {
            $0.draftCrop = CGRect(x: 60, y: 50, width: 40, height: 30)
        }
        await store.send(.dragEnded) {
            $0.draftCrop = nil
            $0.undoStack = [ScreenshotEditDocument(pixelSize: self.size)]
            $0.document.crop = CGRect(x: 60, y: 50, width: 40, height: 30)
        }
        // A new crop drag replaces the crop in one undo step; a 3×3 drag at the corner grows to 8×8 inside the image.
        await store.send(.dragChanged(start: CGPoint(x: 97, y: 77), current: CGPoint(x: 100, y: 80))) {
            $0.draftCrop = CGRect(x: 97, y: 77, width: 3, height: 3)
        }
        await store.send(.dragEnded) {
            $0.draftCrop = nil
            $0.undoStack.append($0.document)
            $0.document.crop = CGRect(x: 92, y: 72, width: 8, height: 8)
        }
        #expect(store.state.document.clampedCrop(CGRect(x: 10.4, y: 10.6, width: 20.2, height: 20)) == CGRect(x: 10, y: 10, width: 21, height: 21))
        await store.send(.resetCrop) { $0.undoStack.append($0.document); $0.document.crop = nil }
        await store.send(.resetCrop)
        await store.send(.undo) { $0.redoStack = [$0.document]; $0.document = $0.undoStack.removeLast() }
        #expect(store.state.document.crop == CGRect(x: 92, y: 72, width: 8, height: 8))
    }

    @Test func taskLoadsImageAndPixelSize() async throws {
        let folder = try makeTemporaryDirectory()
        let url = try writePNG(to: folder.appendingPathComponent("Shot.png"), width: 100, height: 80)
        var client = ScreenshotsClient.testValue
        client.fileURL = { [itemID] id in id == itemID ? url : nil }
        let store = makeStore(.init(itemID: itemID), client: client)
        await store.send(.task) { $0.isLoading = true }
        await store.receive(\.imageLoaded.success) {
            $0.isLoading = false
            $0.image = ScreenshotEditorImage(cgImage: try #require(ScreenshotRenderer.loadImage(at: url)), fileURL: url, type: .png)
            $0.document.pixelSize = self.size
        }
        let previewBlur = try #require(store.state.image?.blurredImage)
        #expect(previewBlur.width == 100 && previewBlur.height == 80)
        let loadedSource = try #require(ScreenshotRenderer.loadImage(at: url))
        let expectedBlur = try #require(ScreenshotRenderer.blurredImage(loadedSource))
        #expect(PixelBuffer(previewBlur).bytes == PixelBuffer(expectedBlur).bytes)
        await store.send(.task)

        var missing = ScreenshotsClient.testValue
        missing.fileURL = { _ in nil }
        let failing = makeStore(.init(itemID: itemID), client: missing)
        await failing.send(.task) { $0.isLoading = true }
        await failing.receive(\.imageLoaded.failure) { $0.isLoading = false; $0.error = ScreenshotFailure(key: ScreenshotFailure.notFoundKey, itemID: self.itemID) }
    }

    @Test func saveRendersEncodesAndReplacesRecordedItem() async throws {
        let folder = try makeTemporaryDirectory()
        let url = try writePNG(to: folder.appendingPathComponent("Shot.png"), width: 100, height: 80, color: (0, 0, 1))
        let written = LockIsolated<[(UUID, Data)]>([])
        let updated = [ScreenshotItem(id: itemID, fileName: "Shot.png", createdAt: Date(timeIntervalSince1970: 1), revision: 1)]
        var client = ScreenshotsClient.testValue
        client.replaceImage = { id, data in written.withValue { $0.append((id, data)) }; return updated }
        var state = loaded()
        state.image = ScreenshotEditorImage(cgImage: try #require(ScreenshotRenderer.loadImage(at: url)), fileURL: url, type: .png)
        state.document.annotations = [.rectangle(CGRect(x: 0, y: 0, width: 20, height: 20), AnnotationStyle(color: RGBAColor(red: 1, green: 0, blue: 0), lineWidth: 4))]
        state.document.crop = CGRect(x: 0, y: 0, width: 50, height: 40)
        let store = makeStore(state, client: client)

        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.success) { $0.isSaving = false }
        await store.receive(.delegate(.finished(updatedItems: updated)))

        let (id, data) = try #require(written.value.first)
        #expect(written.value.count == 1 && id == itemID)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 50 && image.height == 40)
        let pixels = PixelBuffer(image)
        #expect(pixels.pixel(1, 10) == RGBA(r: 255, g: 0, b: 0, a: 255))
        #expect(pixels.pixel(40, 30) == RGBA(r: 0, g: 0, b: 255, a: 255))
    }

    @Test func saveFailureKeepsEditorOpenWithError() async throws {
        let folder = try makeTemporaryDirectory()
        let url = try writePNG(to: folder.appendingPathComponent("Shot.png"), width: 100, height: 80)
        var client = ScreenshotsClient.testValue
        client.replaceImage = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        var state = loaded()
        state.image = ScreenshotEditorImage(cgImage: try #require(ScreenshotRenderer.loadImage(at: url)), fileURL: url, type: .png)
        let store = makeStore(state, client: client)
        let failure = ScreenshotFailure(key: ScreenshotFailure.saveFailedKey, itemID: itemID)
        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.failure) { $0.isSaving = false; $0.error = failure }
        await store.send(.errorDismissed) { $0.error = nil }

        // Without a loaded image there is nothing to save.
        let unloaded = makeStore(.init(itemID: itemID))
        await unloaded.send(.saveTapped)
    }

    @Test func cancelFinishesWithoutWriting() async throws {
        // testValue reports any replaceImage call as an unimplemented dependency.
        var state = loaded()
        state.document.annotations = [.blur(CGRect(x: 0, y: 0, width: 10, height: 10))]
        let store = makeStore(state)
        await store.send(.cancelTapped)
        await store.receive(.delegate(.finished(updatedItems: nil)))

        var saving = loaded()
        saving.isSaving = true
        saving.image = ScreenshotEditorImage(cgImage: try fixtureImage(), fileURL: URL(fileURLWithPath: "/OnlySwitchFixture/Shot.png"), type: .png)
        let busy = makeStore(saving)
        // Cancel and a second Save are ignored while a save is in flight.
        await busy.send(.cancelTapped)
        await busy.send(.saveTapped)
    }
}
#endif
