import ComposableArchitecture

@MainActor
final class DockPreviewController {
    let store: StoreOf<DockPreviewFeature>

    init(
        store: StoreOf<DockPreviewFeature> = Store(initialState: DockPreviewFeature.State()) {
            DockPreviewFeature()
        }
    ) {
        self.store = store
    }

    func start(isEnabled: Bool) {
        store.send(.startup(isEnabled: isEnabled))
    }

    func setEnabled(_ isEnabled: Bool) {
        store.send(.enabledChanged(isEnabled))
    }

    func updatePreviewFrame(_ frame: CGRect?) {
        store.send(.previewFrameChanged(frame))
    }

    func stop() {
        store.send(.stop)
    }
}

