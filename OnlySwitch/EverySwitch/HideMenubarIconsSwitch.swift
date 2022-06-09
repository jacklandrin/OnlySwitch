//
//  HideMenubarIconsSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/6/8.
//

import Foundation

class HideMenubarIconsSwitch:SwitchProvider {
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
    
    func currentStatus() -> Bool {
        return isMenubarCollapse
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    func operationSwitch(isOn: Bool) async throws {
        if isOn {
            guard let isButtonPositionValid = isButtonPositionValid, isButtonPositionValid() else {
                throw SwitchError.OperationFailed
            }
        }
        
        isMenubarCollapse = isOn
        autoCollapseIfNeeded()
    }
    
    func isVisable() -> Bool {
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
            DispatchQueue.main.async {
                if Preferences.shared.isAutoCollapseMenubar {
                    self?.isMenubarCollapse = true
                }
            }
        }
        RunLoop.current.add(self.timer!, forMode: .common)
    }
}
