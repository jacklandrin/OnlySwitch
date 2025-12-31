//
//  PomodoroTimerSettingView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/26.
//

import SwiftUI

struct PomodoroTimerSettingView: View {
    @StateObject var ptSettingVM = PomodoroTimerSettingVM()
    @ObservedObject var effectSoundHelper = EffectSoundHelper.shared
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Form {
            // MARK: - Timer Section
            Section {
                Picker("Work:".localized(), selection: Binding(
                    get: { ptSettingVM.workDuration / 60 },
                    set: { ptSettingVM.workDuration = $0 * 60 }
                )) {
                    ForEach(ptSettingVM.workDurationList, id: \.self) { duration in
                        Text("%d min".localizeWithFormat(arguments: duration)).tag(Int(duration))
                    }
                }
                .pickerStyle(.menu)
                
                Picker("Break:".localized(), selection: Binding(
                    get: { ptSettingVM.restDuration / 60 },
                    set: { ptSettingVM.restDuration = $0 * 60 }
                )) {
                    ForEach(ptSettingVM.restDurationList, id: \.self) { duration in
                        Text("%d min".localizeWithFormat(arguments: duration)).tag(Int(duration))
                    }
                }
                .pickerStyle(.menu)
                
                Picker("Cycle Count:".localized(), selection: $ptSettingVM.cycleCount) {
                    ForEach(ptSettingVM.cycleCountList, id: \.self) { count in
                        Text(cycleCountText(count: count).localized()).tag(count)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Timer".localized())
            }
            
            // MARK: - Alerts Section
            Section {
                Toggle("Allow notification alert".localized(), isOn: $ptSettingVM.allowNotificationAlert)
                
                Toggle("Turn on sound alert".localized(), isOn: $effectSoundHelper.canPlayEffectSound)
                
                HStack {
                    Text("Work Alert:".localized())
                    Spacer()
                    Picker("", selection: $ptSettingVM.workAlert) {
                        ForEach(ptSettingVM.alertSounds, id: \.self) { sound in
                            Text(sound.alertNameConvert()).tag(sound.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    
                    Button {
                        effectSoundHelper.playSound(name: ptSettingVM.workAlert, type: "wav")
                    } label: {
                        Image(systemName: "play.circle")
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                    .buttonStyle(.plain)
                    .disabled(!effectSoundHelper.canPlayEffectSound)
                }
                
                HStack {
                    Text("Break Alert:".localized())
                    Spacer()
                    Picker("", selection: $ptSettingVM.restAlert) {
                        ForEach(ptSettingVM.alertSounds, id: \.self) { sound in
                            Text(sound.alertNameConvert()).tag(sound.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    
                    Button {
                        effectSoundHelper.playSound(name: ptSettingVM.restAlert, type: "wav")
                    } label: {
                        Image(systemName: "play.circle")
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                    .buttonStyle(.plain)
                    .disabled(!effectSoundHelper.canPlayEffectSound)
                }
            } header: {
                Text("Alerts".localized())
            }
        }
        .formStyle(.grouped)
    }
    
    func cycleCountText(count:Int) -> String {
        if count == 0 {
            return "Unlimited"
        } else {
            return String(count)
        }
    }
}

#if DEBUG
struct PomodoroTimer_Previews: PreviewProvider {
    static var previews: some View {
        PomodoroTimerSettingView()
    }
}
#endif
