//
//  PomodoroTimerSettingView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/26.
//

import SwiftUI

struct PomodoroTimerSettingView: View {
    @ObservedObject var ptSettingVM = PomodoroTimerSettingVM()
    @ObservedObject var effectSoundHelper = EffectSoundHelper.shared
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack {
            VStack(alignment:.trailing, spacing: 25) {
                Text("Work:".localized())
                    .frame(height:30)
                Text("Break:".localized())
                    .frame(height:30)
                Text("Notification Alert:".localized())
                    .frame(height:30)
                Text("Sound Alert:".localized())
                    .frame(height:30)
                Text("Work Alert:".localized())
                    .frame(height:30)
                Text("Break Alert:".localized())
                    .frame(height:30)
            }
            VStack(alignment:.leading, spacing: 25) {
                MenuButton(label: Text("%d min".localizeWithFormat(arguments: ptSettingVM.workDuration / 60))) {
                    
                    ForEach(ptSettingVM.workDurationList, id:\.self) { duration in
                        Button("%d min".localizeWithFormat(arguments: duration)) {
                            ptSettingVM.workDuration = Int(duration) * 60
                        }
                    }
                }
                .frame(height: 30)
                
                MenuButton(label: Text("%d min".localizeWithFormat(arguments: ptSettingVM.restDuration / 60))) {
                    
                    ForEach(ptSettingVM.restDurationList, id:\.self) { duration in
                        Button("%d min".localizeWithFormat(arguments: duration)) {
                            ptSettingVM.restDuration = Int(duration) * 60
                        }
                    }
                }
                .frame(height: 30)
                
                Toggle("Allow notification alert".localized(), isOn: $ptSettingVM.allowNotificationAlert)
                    .frame(height: 30)
                
                Toggle("Turn on sound alert".localized(),isOn: $effectSoundHelper.canPlayEffectSound)
                    .frame(height: 30)
                
                HStack {
                    MenuButton(label: Text(EffectSound(rawValue: ptSettingVM.workAlert)!.alertNameConvert())) {
                        
                        ForEach(ptSettingVM.alertSounds, id:\.self) { sound in
                            Button(sound.alertNameConvert()) {
                                ptSettingVM.workAlert = sound.rawValue
                            }
                        }
                    }
                    .frame(height: 30)
                    
                    Button(action: {
                        effectSoundHelper.playSound(name: ptSettingVM.workAlert, type: "wav")
                    }, label: {
                        Image(systemName: "play.circle")
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }).buttonStyle(.plain)
                        .padding(.leading, 5)
                }.disabled(!effectSoundHelper.canPlayEffectSound)
                
                HStack {
                    MenuButton(label: Text(EffectSound(rawValue: ptSettingVM.restAlert)!.alertNameConvert())) {
                        
                        ForEach(ptSettingVM.alertSounds, id:\.self) { sound in
                            Button(sound.alertNameConvert()) {
                                ptSettingVM.restAlert = sound.rawValue
                            }
                        }
                    }
                    .frame(height: 30)
                    
                    Button(action: {
                        effectSoundHelper.playSound(name: ptSettingVM.restAlert, type: "wav")
                    }, label: {
                        Image(systemName: "play.circle")
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }).buttonStyle(.plain)
                        .padding(.leading, 5)
                    
                }.disabled(!effectSoundHelper.canPlayEffectSound)
                
            }.frame(maxWidth:230)
        }
        
    }
}

struct PomodoroTimer_Previews: PreviewProvider {
    static var previews: some View {
        PomodoroTimerSettingView()
    }
}
