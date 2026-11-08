//
//  SoundWaveView.swift
//  SpringRadio
//
//  Created by jack on 2020/4/19.
//  Copyright © 2020 jack. All rights reserved.
//

import SwiftUI

struct SoundWaveView: NSViewRepresentable {
    typealias NSViewType = SpectrumView
    
    var spectra: [[Float]]
    var barWidth: CGFloat
    var space: CGFloat
    var leftColor:[CGColor]
    var rightColor:[CGColor]
    
    func makeNSView(context: Context) -> SpectrumView {
        let view = SpectrumView()
        return view
    }
    
    func updateNSView(_ nsView: SpectrumView, context: Context) {
        nsView.barWidth = barWidth
        nsView.space = space
        nsView.leftColors = leftColor
        nsView.rightColors = rightColor
        guard spectra.count > 0 else {
            return
        }
        nsView.spectra = spectra
    }
}

#if DEBUG
struct SoundWaveView_Previews: PreviewProvider {
    static var previews: some View {
        SoundWaveView(spectra: [[0.0],[0.0]], barWidth: 3.0, space: 0, leftColor: leftColors, rightColor: rightColors)
    }
}
#endif
