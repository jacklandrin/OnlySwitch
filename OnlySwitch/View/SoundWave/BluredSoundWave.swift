//
//  BluredSoundWave.swift
//  SpringRadio
//
//  Created by jack on 2020/4/20.
//  Copyright © 2020 jack. All rights reserved.
//

import SwiftUI

let leftColors = [NSColor(red: 232/255, green: 86/255, blue: 171/255, alpha: 0.7).cgColor,
                  NSColor(red: 196/255, green: 95/255, blue: 187/255, alpha: 0.8).cgColor]
let rightColors = [NSColor(red: 133/255, green: 116/255, blue: 210/255, alpha: 0.5).cgColor,
                   NSColor(red: 92/255, green: 234/255, blue: 230/255, alpha: 0.6).cgColor]


struct BluredSoundWave: View {
    @StateObject var soundWave:SoundWaveVM = SoundWaveVM()
    var body: some View {
        SoundWaveView(spectra: self.soundWave.spectra, barWidth: self.soundWave.barWidth, space: self.soundWave.space, leftColor: leftColors, rightColor: rightColors)
            .onReceive(NotificationCenter.default.publisher(for: .spectra)) { notification in
                let spectra = notification.object as! [[Float]]
                self.soundWave.setSpectra(spectra: spectra)
            }
            .frame(width: Layout.soundWaveWidth, height:Layout.soundWaveHeight)
            .blur(radius: 7.5)
            
    }
}

struct BluredSoundWave_Previews: PreviewProvider {
    static var previews: some View {
        BluredSoundWave()
    }
}
