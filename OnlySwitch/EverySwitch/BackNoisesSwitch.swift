//
//  BackNoisesSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/11.
//

import Foundation
import Switches

class BackNoisesSwitch: SwitchProvider {
    
    var type: SwitchType = .backNoises
    
    var delegate: SwitchDelegate?
    
    let backNoisesTrackManager = BackNoisesTrackManager.shared
    
    private var timer:Timer? = nil
    
    init() {
        NotificationCenter.default.addObserver(forName: .changeAutoStopNoiseTime, object: nil, queue: .main) { [weak self] _ in
            self?.autoStopNoisesIfNeeded()
        }
    }
    
    func currentStatus() -> Bool {
        backNoisesTrackManager.currentBackNoisesItem.isPlaying
    }
    
    func currentInfo() -> String {
        backNoisesTrackManager.currentBackNoisesItem.title
    }
    
    func operateSwitch(isOn: Bool) async throws {
        DispatchQueue.main.async {
            if isOn {
                self.backNoisesTrackManager.currentBackNoisesItem.isPlaying = true
                if let url = self.backNoisesTrackManager.currentBackNoisesItem.url, !fileExistAtPath(url.absoluteString) {
                    self.backNoisesTrackManager.currentTrack = self.backNoisesTrackManager.currentBackNoisesItem.track
                }
            } else {
                self.backNoisesTrackManager.currentBackNoisesItem.isPlaying = false
            }
            self.autoStopNoisesIfNeeded()
        }
    }
    
    func isVisible() -> Bool {
        return Preferences.shared.radioEnable
    }

    private func autoStopNoisesIfNeeded() {
        timer?.invalidate()
        guard backNoisesTrackManager.currentBackNoisesItem.isPlaying,
        Preferences.shared.isAutoStopNoise else {
            return
        }
        
        self.startTimer()
    }
    
    private func startTimer() {
        timer?.invalidate()
        self.timer = Timer(timeInterval: TimeInterval(Preferences.shared.automaticallyStopPlayNoiseTime * 60),
                           repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.backNoisesTrackManager.currentBackNoisesItem.isPlaying = false
                NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: SwitchType.backNoises)
            }
        }
        RunLoop.current.add(self.timer!, forMode: .common)
    }
    
}

