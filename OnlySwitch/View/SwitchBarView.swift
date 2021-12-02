//
//  SwitchBarView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/1.
//

import SwiftUI

struct SwitchBarView: View {
    @EnvironmentObject var switchOption:SwitchBarVM

    var body: some View {
        HStack {
            Image(nsImage:
                    barImage(option: switchOption))
                .resizable()
                .scaledToFit()
                .frame(width: 25 , height: 25)
            Text(switchOption.switchType.switchTitle().title)
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.8)
                .isHidden(!switchOption.processing,remove: true)
            SwitchToggle(isOn: $switchOption.isOn) { isOn in
                switchOption.doSwitch(isOn: isOn)
            }.disabled(switchOption.processing)
            .animation(.spring(), value: switchOption.isOn)
            .scaleEffect(0.8)
        }.isHidden(switchOption.isHidden, remove: true)
    }
    
    func barImage(option:SwitchBarVM) -> NSImage {
        if option.isOn {
            return option.switchType.switchTitle().onImage
        } else {
            return option.switchType.switchTitle().offImage
        }
    }

}

struct SwitchBar_Previews: PreviewProvider {
    static var previews: some View {
        SwitchBarView()
            .environmentObject(SwitchBarVM(switchType: .topNotch))
            .frame(width: 300)
    }
}
