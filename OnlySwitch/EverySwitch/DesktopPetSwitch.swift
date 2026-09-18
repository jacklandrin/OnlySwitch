import Defines
import Switches

final class DesktopPetSwitch: SwitchProvider, @unchecked Sendable {
    weak var delegate: SwitchDelegate?
    let type: SwitchType = .desktopPet

    private let visibility: @MainActor @Sendable () -> Bool
    private let setVisibility: @MainActor @Sendable (Bool) -> Void

    init(
        visibility: @escaping @MainActor @Sendable () -> Bool = {
            Preferences.shared.showDesktopPet
        },
        setVisibility: @escaping @MainActor @Sendable (Bool) -> Void = { isVisible in
            Preferences.shared.showDesktopPet = isVisible
        }
    ) {
        self.visibility = visibility
        self.setVisibility = setVisibility
    }

    @MainActor
    func currentStatus() async -> Bool {
        visibility()
    }

    @MainActor
    func currentInfo() async -> String {
        ""
    }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        setVisibility(isOn)
    }

    func isVisible() -> Bool {
        true
    }
}
