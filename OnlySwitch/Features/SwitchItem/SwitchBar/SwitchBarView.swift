//
//  SwitchBarView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/1.
//

import Defines
import Design
import SwiftUI
import Switches
import Utilities

struct SwitchBarView: View {
    @EnvironmentObject var switchOption:SwitchBarVM
    @ObservedObject private var languageManager = LanguageManager.sharedManager
    var body: some View {
        HStack {
            Image(nsImage:
                    barImage(option: switchOption)!
                .resizeMaintainingAspectRatio(withSize: NSSize(width: 50, height: 50))!)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: Layout.iconSize, height: Layout.iconSize)
            .padding(.trailing, 8)
            
            Text(switchOption.title.localized())
                .font(.system(size: 14))
                .frame(alignment: .leading)
            
            if switchOption.switchType == .airPods {
                AirPodsBatteryView(batteryValues: convertBattery(info: switchOption.info))
            } else if switchOption.switchType == .pomodoroTimer {
                TimerCountDownView(ptswitch: switchOption.switchOperator as! PomodoroTimerSwitch)
            }
            else {
                Text(switchOption.info.localized())
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            AppKitProgressView()
                .scaleEffect(0.6)
                .isHidden(!switchOption.processing, remove: true)
            
            switch switchOption.controlType {
                case .Switch:
                    SwitchToggle(isOn: $switchOption.isOn) { isOn in
                        Task {
                            await switchOption.doSwitch(isOn: isOn)
                        }
                    }
                    .disabled(switchOption.processing)
                    .animation(.spring(), value: switchOption.isOn)
                    .scaleEffect(0.8)
                    
                case .Button:
                    Button {
                        Task {
                            await switchOption.doSwitch(isOn: true)
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 15)
                                .foregroundColor(.accentColor)
                                .frame(height:26)
                            Text(buttonTitle(category:switchOption.category).localized())
                                .font(.system(size: buttonTitle(category:switchOption.category).localized().count > 6 ? 300 : 12))
                                .lineLimit(1)
                                .minimumScaleFactor(0.02)
                                .foregroundColor(.white)
                        }
                        .frame(width: 46, height: 30)
                    }
                    .buttonStyle(.plain)
                    .shadow(radius: 2)
                    .padding(.horizontal, 6)
                    
                case .Player:
                    Button {
                        Task {
                            await switchOption.doSwitch(isOn: !switchOption.isOn)
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 15)
                                .foregroundColor(.accentColor)
                                .frame(height:26)
                            Image(systemName: switchOption.isOn ? "pause.fill" : "play.fill")
                                .foregroundColor(.white)
                        }.frame(width: 46, height: 30)
                    }
                    .buttonStyle(.plain)
                    .shadow(radius: 2)
                    .padding(.horizontal, 6)
            }
        }
        .isHidden(switchOption.isHidden, remove: true)
        .alert(item: $switchOption.privilegedHelperRecovery) { recovery in
            switch recovery {
            case .install:
                Alert(
                    title: Text("One-time authorization required".localized()),
                    message: Text("Install OnlySwitch's privileged helper once to change Low Power Mode without repeated password prompts.".localized()),
                    primaryButton: .default(Text("Install & Authorize".localized())) {
                        Task { @MainActor [switchOption] in
                            await switchOption.installPrivilegedHelper()
                        }
                    },
                    secondaryButton: .cancel()
                )
            case .openSystemSettings:
                Alert(
                    title: Text("Authorization approval needed".localized()),
                    message: Text("Approve OnlySwitch's privileged helper in System Settings to continue.".localized()),
                    primaryButton: .default(Text("Open System Settings".localized())) {
                        Task { @MainActor [switchOption] in
                            await switchOption.openPrivilegedHelperSettings()
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
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
