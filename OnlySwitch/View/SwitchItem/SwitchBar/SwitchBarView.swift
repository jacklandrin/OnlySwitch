//
//  SwitchBarView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/1.
//

import SwiftUI
import Switches

struct SwitchBarView: View {
    @EnvironmentObject var switchOption:SwitchBarVM
    @ObservedObject private var languageManager = LanguageManager.sharedManager
    var body: some View {
        HStack {
            Image(nsImage:
                    barImage(option: switchOption)!.resizeMaintainingAspectRatio(withSize: NSSize(width: 50, height: 50))!)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 25, height: 25)
            .padding(.trailing, 8)
            
            Text(switchOption.title.localized())
                .font(.system(size: 14))
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
                .isHidden(!switchOption.processing, remove: true)
            
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
                            .foregroundColor(.accentColor)
                            .frame(height:26)
                        Text(buttonTitle(category:switchOption.category).localized())
                            .font(.system(size: buttonTitle(category:switchOption.category).localized().count > 6 ? 300 : 12))
                            .lineLimit(1)
                            .minimumScaleFactor(0.02)
                            .foregroundColor(.white)
                    }.frame(width: 46, height: 30)
                }).buttonStyle(.plain)
                    .shadow(radius: 2)
                    .padding(.horizontal, 6)
            case .Player:
                Button(action: {
                    switchOption.doSwitch(isOn: !switchOption.isOn)
                }, label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15)
                            .foregroundColor(.accentColor)
                            .frame(height:26)
                        Image(systemName: switchOption.isOn ? "pause.fill" : "play.fill")
                            .foregroundColor(.white)
                    }.frame(width: 46, height: 30)
                }).buttonStyle(.plain)
                    .shadow(radius: 2)
                    .padding(.horizontal, 6)
            }
        }
        .isHidden(switchOption.isHidden, remove: true)
    }
    
    func buttonTitle(category:SwitchCategory) -> String {
        if category == .cleanup {
            return "Clear"
        } else if category == .tool {
            return "Run"
        } else {
            return ""
        }
    }
    
    func barImage(option:SwitchBarVM) -> NSImage? {
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

#if DEBUG
struct SwitchBar_Previews: PreviewProvider {
    static var previews: some View {
        SwitchBarView()
            .environmentObject(SwitchBarVM(switchOperator: PomodoroTimerSwitch.shared))
            .frame(width: 300)
    }
}
#endif
