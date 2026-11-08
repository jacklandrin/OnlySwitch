import Defines
import Switches

final class DockPreviewSwitch: SwitchProvider, @unchecked Sendable {
    weak var delegate: SwitchDelegate?
    let type: SwitchType = .dockPreview

    private let enabled: @MainActor @Sendable () -> Bool
    private let setEnabled: @MainActor @Sendable (Bool) -> Void

    init(
        enabled: @escaping @MainActor @Sendable () -> Bool = {
            Preferences.shared.dockPreviewEnabled
        },
        setEnabled: @escaping @MainActor @Sendable (Bool) -> Void = { isEnabled in
            Preferences.shared.dockPreviewEnabled = isEnabled
        }
    ) {
        self.enabled = enabled
        self.setEnabled = setEnabled
    }

    @MainActor
    func currentStatus() async -> Bool {
        enabled()
    }

    @MainActor
    func currentInfo() async -> String {
        ""
    }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        setEnabled(isOn)
    }

    func isVisible() -> Bool {
        true
    }
}
