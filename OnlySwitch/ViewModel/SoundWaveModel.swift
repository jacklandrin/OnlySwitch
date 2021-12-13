//
//  SoundWaveModel.swift
//  SpringRadio
//
//  Created by jack on 2020/4/19.
//  Copyright © 2020 jack. All rights reserved.
//

import AppKit
import Combine

class SoundWaveModel: ObservableObject {
    @Published var spectra: [[Float]] = [[Float]]()
    
    @Published var barWidth:CGFloat = 3.0
    @Published var space:CGFloat = 0.0
    
    init() {
        self.setSpectrum()
        self.setBarWidth()
    }
    
    func setSpectrum(){
        NotificationCenter.default.addObserver(forName: spectraNofiticationName, object: nil, queue: .main, using: {[weak self] notification in
            guard let strongSelf = self else {return}
            let spectra = notification.object as! [[Float]]
            strongSelf.spectra = spectra
        })
    }
    
    func setBarWidth() {
        let barSpace = soundWaveWidth / CGFloat(PlayerManager.shared.player.analyzer.frequencyBands * 3 - 1)
        self.barWidth = barSpace * 3
    }
}
