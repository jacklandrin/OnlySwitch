import Defines
import Extensions
import Foundation
import Switches

final class AppUninstallerSwitch: SwitchProvider, Sendable {
    private let delegateBox = AppUninstallerWeakDelegateBox()
    var delegate: SwitchDelegate? {
        get { delegateBox.value }
        set { delegateBox.value = newValue }
    }
    let type: SwitchType = .appUninstaller
    private let visibility: @MainActor @Sendable () -> Bool
    private let setVisibility: @MainActor @Sendable (Bool) -> Void
    private let notifySettingsChanged: @MainActor @Sendable () -> Void

    init(
        visibility: @escaping @MainActor @Sendable () -> Bool = {
            UserDefaults.standard.object(forKey: UserDefaults.Key.showAppUninstallerTab) as? Bool ?? true
        },
        setVisibility: @escaping @MainActor @Sendable (Bool) -> Void = {
            UserDefaults.standard.set($0, forKey: UserDefaults.Key.showAppUninstallerTab)
        },
        notifySettingsChanged: @escaping @MainActor @Sendable () -> Void = {
            NotificationCenter.default.post(name: .changeSettings, object: nil)
        }
    ) {
        self.visibility = visibility; self.setVisibility = setVisibility
        self.notifySettingsChanged = notifySettingsChanged
    }

    @MainActor func currentStatus() async -> Bool { visibility() }
    @MainActor func currentInfo() async -> String { "" }
    @MainActor func operateSwitch(isOn: Bool) async throws {
        setVisibility(isOn)
        notifySettingsChanged()
    }
    func isVisible() -> Bool { true }
}

/// Thread-safe storage for the protocol's synchronous weak delegate requirement.
private final class AppUninstallerWeakDelegateBox: @unchecked Sendable {
    private let lock = NSLock()
    private weak var storedValue: SwitchDelegate?
    var value: SwitchDelegate? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            storedValue = newValue
            lock.unlock()
        }
    }
}
