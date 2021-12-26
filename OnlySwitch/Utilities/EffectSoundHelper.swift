//
//  EffectSoundHelper.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/26.
//

import AVFoundation

class EffectSoundHelper:ObservableObject {
    var player = AVAudioPlayer()
    
    static let shared = EffectSoundHelper()
    
    @UserDefaultValue(key: "canPlayESKey", defaultValue: true)
    var canPlayEffectSound:Bool
    {
        didSet {
            objectWillChange.send()
        }
    }
    
    func playSound(name:String, type:String) {
        guard self.canPlayEffectSound else {
            return
        }
        
        guard let soundURL = Bundle.main.path(forResource: name, ofType: type) else {
            return
        }
        
        if let audioPlayer = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: soundURL)) {
            if self.player.isPlaying {
                self.player.stop()
            }
            self.player = audioPlayer
            self.player.numberOfLoops = 0
            self.player.play()
        }
    }
}

enum EffectSound:String {
    case alertBells = "mixkit-alert-bells-echo-765"
    case bellNotification = "mixkit-bell-notification-933"
    
    func alertNameConvert() -> String {
        switch self {
        case .alertBells:
            return "Alert Bell"
        case .bellNotification:
            return "Bell Notification"
        }
    }
}
