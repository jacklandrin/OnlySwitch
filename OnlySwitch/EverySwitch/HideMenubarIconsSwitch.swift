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

final class HideMenubarIconsSwitch: SwitchProvider {
    static let shared = HideMenubarIconsSwitch()
    var type: SwitchType = .hideMenubarIcons
    
    var delegate: SwitchDelegate?
    var isButtonPositionValid:(() -> Bool)?
    
    private var timer:Timer? = nil
    
    @UserDefaultValue(key: UserDefaults.Key.isMenubarCollapse, defaultValue: false)
    private var isMenubarCollapse:Bool {
        didSet {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .toggleMenubarCollapse, object: self.isMenubarCollapse)
            }
        }
    }
    
    init() {
        NotificationCenter.default.addObserver(forName: .changeAutoMenubarCollapseTime, object: nil, queue: .main) { [weak self] _ in
            self?.timer?.invalidate()
            self?.autoCollapseIfNeeded()
        }
    }

    @MainActor
    func currentStatus() async -> Bool {
        return isMenubarCollapse
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
        
        isMenubarCollapse = isOn
        autoCollapseIfNeeded()
    }
    
    func isVisible() -> Bool {
        return Preferences.shared.menubarCollaspable
    }
    
    private func autoCollapseIfNeeded() {
        timer?.invalidate()
        guard Preferences.shared.isAutoCollapseMenubar else {return}
        guard !isMenubarCollapse else { return }
        DispatchQueue.main.async {
            self.startTimerToCollapse()
        }
    }
    
    private func startTimerToCollapse() {
        timer?.invalidate()
        self.timer = Timer(timeInterval: TimeInterval(Preferences.shared.autoCollapseMenubarTime), repeats: false) { [weak self] _ in
            guard let isButtonPositionValid = self?.isButtonPositionValid,
                  isButtonPositionValid() else {
                return
            }
            DispatchQueue.main.async {
                if Preferences.shared.isAutoCollapseMenubar {
                    self?.isMenubarCollapse = true
                }
            }
        }
        RunLoop.current.add(self.timer!, forMode: .common)
    }
}
