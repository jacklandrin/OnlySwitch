//
//  SoundWaveModel.swift
//  SpringRadio
//
//  Created by jack on 2020/4/19.
//  Copyright © 2020 jack. All rights reserved.
//

import AppKit
import Combine

class SoundWaveVM: ObservableObject {
//    @Published var spectra: [[Float]] = [[Float]]()
//
//    @Published var barWidth:CGFloat = 3.0
//    @Published var space:CGFloat = 0.0
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
    
    init() {
        self.setBarWidth()
    }
        
    func setSpectra(spectra:[[Float]]) {
        model.spectra = spectra
    }
    
    func setBarWidth() {
        let barSpace = Layout.soundWaveWidth / CGFloat(PlayerManager.shared.player.analyzer.frequencyBands * 3 - 1)
        self.model.barWidth = barSpace * 3
    }
}
