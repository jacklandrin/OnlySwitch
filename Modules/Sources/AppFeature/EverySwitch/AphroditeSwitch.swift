import Defines
import Extensions
import Foundation
import Switches

final class AphroditeSwitch: SwitchProvider, Sendable {
    private let delegateBox = AphroditeWeakDelegateBox()
    var delegate: SwitchDelegate? {
        get { delegateBox.value }
        set { delegateBox.value = newValue }
    }
    let type: SwitchType = .aphrodite
    private let visibility: @MainActor @Sendable () -> Bool
    private let setVisibility: @MainActor @Sendable (Bool) -> Void

    init(
        visibility: @escaping @MainActor @Sendable () -> Bool = {
            UserDefaults.standard.object(forKey: UserDefaults.Key.showAphroditeTab) as? Bool ?? true
        },
        setVisibility: @escaping @MainActor @Sendable (Bool) -> Void = {
            UserDefaults.standard.set($0, forKey: UserDefaults.Key.showAphroditeTab)
        }
    ) { self.visibility = visibility; self.setVisibility = setVisibility }

    @MainActor func currentStatus() async -> Bool { visibility() }
    @MainActor func currentInfo() async -> String { "" }
    @MainActor func operateSwitch(isOn: Bool) async throws {
        setVisibility(isOn)
        NotificationCenter.default.post(name: .changeSettings, object: nil)
    }
    func isVisible() -> Bool { true }
}

/// Thread-safe storage for the protocol's synchronous weak delegate requirement.
private final class AphroditeWeakDelegateBox: @unchecked Sendable {
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
