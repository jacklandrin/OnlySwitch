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
        guard Preferences.shared.isAutoCollapseMenubar else {return}
        guard persistedState == false else { return }
        startTimerToCollapse()
    }
    
    @MainActor
    private func startTimerToCollapse() {
        timer?.invalidate()
        self.timer = Timer(timeInterval: TimeInterval(Preferences.shared.autoCollapseMenubarTime), repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, Preferences.shared.isAutoCollapseMenubar else { return }
                do {
                    try await self.operateSwitch(isOn: true)
                } catch {
                    // A denied permission or unavailable native API must leave
                    // the persisted state expanded.
                }
            }
        }
        RunLoop.current.add(self.timer!, forMode: .common)
    }
}
