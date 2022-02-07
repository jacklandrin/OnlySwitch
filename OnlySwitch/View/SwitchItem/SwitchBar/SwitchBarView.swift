//
//  SwitchBarView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/1.
//

import SwiftUI

struct SwitchBarView: View {
    @EnvironmentObject var switchOption:SwitchBarVM
    @ObservedObject private var languageManager = LanguageManager.sharedManager
    var body: some View {
        HStack {
            Image(nsImage:
                    barImage(option: switchOption).resizeMaintainingAspectRatio(withSize: NSSize(width: 50, height: 50))!)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 25, height: 25)
            
            Text(switchOption.title.localized())
                .frame(alignment: .leading)
            if switchOption.switchType == .airPods {
                AirPodsBatteryView(batteryValues: convertBattery(info: switchOption.info))
                    .offset(x:60)
            } else if switchOption.switchType == .pomodoroTimer {
                TimerCountDownView(ptswitch: switchOption.switchOperator as! PomodoroTimerSwitch)
            }
            else {
                Text(switchOption.info.localized())
                    .foregroundColor(.gray)
            }
            
            Spacer()
        
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
//                .scaleEffect(0.8)
                .isHidden(!switchOption.processing,remove: true)
            
            switch switchOption.controlType {
            case .Switch:
                SwitchToggle(isOn: $switchOption.isOn) { isOn in
                    switchOption.doSwitch(isOn: isOn)
                }.disabled(switchOption.processing)
                .animation(.spring(), value: switchOption.isOn)
                .scaleEffect(0.8)
            case .Button:
                Button(action: {
                    switchOption.doSwitch(isOn: true)
                }, label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15)
                            .foregroundColor(.blue)
                            .frame(height:26)
                        Text("Clear".localized())
                            .font(.system(size: "Clear".localized().count > 6 ? 300 : 11))
                            .lineLimit(1)
                            .minimumScaleFactor(0.01)
                            .foregroundColor(.white)
                            .font(.system(size: 11))
                    }.frame(width: 46, height: 30)
                }).buttonStyle(.plain)
                    .shadow(radius: 2)
                    .padding(.horizontal, 6)
            }
            
           
        }.isHidden(switchOption.isHidden, remove: true)
    }
    
    func barImage(option:SwitchBarVM) -> NSImage {
        if option.isOn {
            return option.onImage
        } else {
            return option.offImage
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
            .environmentObject(SwitchBarVM(switchOperator: PomodoroTimerSwitch.shared))
            .frame(width: 300)
    }
}
