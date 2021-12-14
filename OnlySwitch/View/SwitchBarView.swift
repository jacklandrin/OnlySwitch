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
                .frame(width: 25, height: 25)
            Text(switchOption.switchOperator!.barInfo.title)
                .frame(alignment: .leading)
            if switchOption.switchType == .airPods {
                AirPodsBatteryView(batteryValues: convertBattery(info: switchOption.info))
                    .offset(x:60)
            } else {
                Text(switchOption.info).foregroundColor(.gray)
            }
            
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
            return option.switchOperator!.barInfo.onImage
        } else {
            return option.switchOperator!.barInfo.offImage
        }
    }

    func convertBattery(info:String) -> [Float] {
        let pattern = "(-?\\d+)"
        let groups = info.groups(for: pattern).compactMap({$0.first}).map{Float($0)! < 0 ? 0.0 : (Float($0)! / 100.0)}
        return groups
    }
    
    
}

struct SwitchBar_Previews: PreviewProvider {
    static var previews: some View {
        SwitchBarView()
            .environmentObject(SwitchBarVM(switchType: .topNotch))
            .frame(width: 300)
    }
}
