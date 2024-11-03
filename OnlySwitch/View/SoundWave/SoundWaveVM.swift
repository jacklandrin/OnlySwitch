//
//  SoundWaveModel.swift
//  SpringRadio
//
//  Created by jack on 2020/4/19.
//  Copyright © 2020 jack. All rights reserved.
//

import AppKit
import Combine

@MainActor
class SoundWaveVM: ObservableObject {
    
    var spectra: [[Float]] {
        return model.spectra
    }
    
    var barWidth:CGFloat {
        return model.barWidth
    }
    
    var space:CGFloat {
        return model.space
    }
    
    @Published private var model = SoundWaveModel()
    
    init(soundWaveWidth:CGFloat) {
        self.setBarWidth(soundWaveWidth: soundWaveWidth)
    }
        
    func setSpectra(spectra:[[Float]]) {
        model.spectra = spectra
    }
    
    func setBarWidth(soundWaveWidth:CGFloat) {
        let barSpace = soundWaveWidth / CGFloat(PlayerManager.shared.player.analyzer.frequencyBands * 3 - 1)
        self.model.barWidth = barSpace * 3
    }
}
