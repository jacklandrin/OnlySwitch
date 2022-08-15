//
//  DimScreenSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/13.
//

import Foundation
import Combine
class DimScreenSwitch:SwitchProvider {
    enum DimScreenError:Error {
        case brightnessTooLow
    }
    
    var type: SwitchType = .dimScreen
    
    var delegate: SwitchDelegate?
    
    private var isDimming:Bool = false {
        didSet {
            timerCounter = 0
        }
    }
    private var manager = DisplayManager()
    private var originalBrightness:Float = 1.0
    private var dimPercent:Float = Preferences.shared.dimScreenPercent
    private var autoDimScreenTime = Preferences.shared.autoDimScreenTime
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var timerCounter = 0
    private var cancellable = Set<AnyCancellable>()
    
    private var durationBySecond:Int {
        autoDimScreenTime * 60 //persistance unit is min, here is second
    }
    
    init() {
        NotificationCenter.default.addObserver(forName: .changeDimScreenSetting, object: nil, queue: .main) { [weak self] _ in
            guard let strongSelf = self else {return}
            if strongSelf.dimPercent != Preferences.shared.dimScreenPercent {
                strongSelf.dimPercent = Preferences.shared.dimScreenPercent
                if strongSelf.isDimming {
                    try? strongSelf.modifyDimPercent()
                }
            }
            strongSelf.autoDimScreenTime = Preferences.shared.autoDimScreenTime
        }
        
        setTimer()
    }
    
    deinit {
        cancellable.removeAll()
    }
    
    func currentStatus() -> Bool {
        return isDimming
    }
    
    func currentInfo() -> String {
        return "Built-in Screen"
    }
    
    func operationSwitch(isOn: Bool) async throws {
        if isOn {
            try dimScreen()
        } else {
            restoreScreen()
        }
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    private func setTimer() {
        timer.sink{ _ in
            guard !self.isDimming, self.autoDimScreenTime != 0 else {return} //switch is on and duration isn't never
            self.timerCounter += 1
            if self.timerCounter == self.durationBySecond {
                self.timerCounter = 0
                try? self.dimScreen()
                NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: self.type)
            }
        }.store(in: &cancellable)
    }
    
    private func dimScreen() throws {
        manager.configureDisplays()
        originalBrightness = manager.getBrightness()
        try modifyDimPercent()
        isDimming = true
    }
    
    private func modifyDimPercent() throws {
        let dimBrightness = originalBrightness * dimPercent
        guard dimBrightness >= 0.15 else { // the minimum brightness is 0.15
            throw DimScreenError.brightnessTooLow
        }
        manager.setBrightness(level: dimBrightness)
    }
    
    private func restoreScreen() {
        manager.configureDisplays()
        manager.setBrightness(level: originalBrightness)
        isDimming = false
    }
}

