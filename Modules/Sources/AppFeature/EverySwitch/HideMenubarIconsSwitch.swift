//
//  HideMenubarIconsSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/6/8.
//

import Foundation
import Switches
import Defines
import Extensions

final class HideMenubarIconsSwitch: SwitchProvider, @unchecked Sendable {
    typealias Transition = @MainActor (Bool) async throws -> Void

    static let shared = HideMenubarIconsSwitch()
    var type: SwitchType = .hideMenubarIcons
    
    var delegate: SwitchDelegate?
    var isButtonPositionValid:(() -> Bool)?
    private(set) var transition: Transition?
    private var transitionOwner: UUID?
    
    private var timer:Timer? = nil
    var isPointerInMenuBar: @MainActor () -> Bool = { MenuBarPointerTracker.isPointerInMenuBar() }
    @MainActor private var pointerLastInMenuBar: Date?
    @MainActor private var trackerStorage: MenuBarPointerTracker?

    @MainActor
    private var pointerTracker: MenuBarPointerTracker {
        if let trackerStorage {
            return trackerStorage
        }
        let tracker = MenuBarPointerTracker { [weak self] in
            self?.pointerLastInMenuBar = Date()
        }
        trackerStorage = tracker
        return tracker
    }
    
    @UserDefaultValue(key: UserDefaults.Key.isMenubarCollapse, defaultValue: false)
    private var isMenubarCollapse:Bool
    private var testPersistedState: Bool?
    
    init() {
        NotificationCenter.default.addObserver(forName: .changeAutoMenubarCollapseTime, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.timer?.invalidate()
                self?.autoCollapseIfNeeded()
            }
        }
    }

    @MainActor
    init(transition: @escaping Transition, persistedState: Bool) {
        self.transition = transition
        self.testPersistedState = persistedState
    }

    @MainActor
    func installTransition(owner: UUID, transition: @escaping Transition) {
        transitionOwner = owner
        self.transition = transition
    }

    @MainActor
    func clearTransition(owner: UUID) {
        guard transitionOwner == owner else { return }
        transitionOwner = nil
        transition = nil
    }

    @MainActor
    func currentStatus() async -> Bool {
        persistedState
    }

    @MainActor
    func currentInfo() async -> String {
        return ""
    }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        if isOn {
            guard let isButtonPositionValid = isButtonPositionValid, isButtonPositionValid() else {
                throw SwitchError.OperationFailed
            }
        }
        
        guard let transition else {
            throw SwitchError.OperationFailed
        }

        do {
            try await transition(isOn)
        } catch {
            throw SwitchError.OperationFailed
        }

        setPersistedState(isOn)
        NotificationCenter.default.post(name: .toggleMenubarCollapse, object: isOn)
        autoCollapseIfNeeded()
    }

    @MainActor
    func resetPersistedStateAfterFailedStartup() {
        timer?.invalidate()
        trackerStorage?.stop()
        setPersistedState(false)
        NotificationCenter.default.post(name: .toggleMenubarCollapse, object: false)
    }
    
    func isVisible() -> Bool {
        return Preferences.shared.menubarCollaspable
    }
    
    @MainActor
    private var persistedState: Bool {
        testPersistedState ?? isMenubarCollapse
    }

    @MainActor
    private func setPersistedState(_ value: Bool) {
        if testPersistedState != nil {
            testPersistedState = value
        } else {
            isMenubarCollapse = value
        }
    }

    @MainActor
    private func autoCollapseIfNeeded() {
        timer?.invalidate()
        trackerStorage?.stop()
        guard Preferences.shared.isAutoCollapseMenubar else {return}
        guard persistedState == false else { return }
        startTimerToCollapse()
    }
    
    @MainActor
    private func startTimerToCollapse() {
        pointerLastInMenuBar = nil
        pointerTracker.start()
        scheduleCollapseCheck(after: autoCollapseInterval)
    }

    @MainActor
    private var autoCollapseInterval: TimeInterval {
        TimeInterval(Preferences.shared.autoCollapseMenubarTime)
    }

    @MainActor
    private func scheduleCollapseCheck(after delay: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.collapseIfPointerStayedAway()
            }
        }
        self.timer = timer
        RunLoop.current.add(timer, forMode: .common)
    }

    @MainActor
    private func collapseIfPointerStayedAway() async {
        guard Preferences.shared.isAutoCollapseMenubar, persistedState == false else {
            pointerTracker.stop()
            return
        }
        let isPointerInMenuBar = isPointerInMenuBar()
        if isPointerInMenuBar {
            pointerLastInMenuBar = Date()
        }
        if let delay = Self.remainingAutoCollapseDelay(
            now: Date(),
            interval: autoCollapseInterval,
            isPointerInMenuBar: isPointerInMenuBar,
            pointerLastInMenuBar: pointerLastInMenuBar
        ) {
            scheduleCollapseCheck(after: delay)
            return
        }
        pointerTracker.stop()
        do {
            try await operateSwitch(isOn: true)
        } catch {
            // A denied permission or unavailable native API must leave
            // the persisted state expanded.
        }
    }

    /// How much longer to wait before hiding, or nil to hide now. The delay restarts whenever the pointer is in the menu bar, so icons stay shown while someone is using or rearranging them.
    nonisolated static func remainingAutoCollapseDelay(
        now: Date,
        interval: TimeInterval,
        isPointerInMenuBar: Bool,
        pointerLastInMenuBar: Date?
    ) -> TimeInterval? {
        if isPointerInMenuBar {
            return interval
        }
        guard let pointerLastInMenuBar else { return nil }
        let remaining = interval - now.timeIntervalSince(pointerLastInMenuBar)
        return remaining > 0 ? remaining : nil
    }
}
