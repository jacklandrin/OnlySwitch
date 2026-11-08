//
//  KeepAwakeSettingView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/12.
//

import SwiftUI

struct KeepAwakeSettingView: View {
    @StateObject var vm = KeepAwakeSettingVM()
    
    var body: some View {
        Form {
            // MARK: - Duration Section
            Section {
                Toggle(isOn: $vm.scheduleMode) {
                    HStack {
                        Text("Keep Awake Until After:".localized())
                        Spacer()
                        Picker("", selection: $vm.currentDuration) {
                            ForEach(vm.durationSet, id: \.self) { duration in
                                Text(vm.converTimeDescription(duration: duration)).tag(duration)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 120)
                    }
                }
            } header: {
                Text("Duration".localized())
            }
            
            // MARK: - Schedule Section
            Section {
                Toggle(isOn: $vm.afterMode) {
                    Text("Daily Schedule:".localized())
                }
                
                DatePicker(
                    "from:".localized(),
                    selection: $vm.startDate,
                    displayedComponents: .hourAndMinute
                )
                
                DatePicker(
                    "to:".localized(),
                    selection: $vm.endDate,
                    displayedComponents: .hourAndMinute
                )
                
            } header: {
                Text("Schedule".localized())
            } footer: {
                if vm.isTomorrow {
                    Text("Tomorrow".localized())
                }
            }
            
            // MARK: - Sleep Section
            Section {
                Toggle(isOn: $vm.stopOnSleep) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Turn off after sleep".localized())
                        Text("Keep Awake turns off when you put your Mac to sleep.".localized())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct KeepAwakeSettingView_Previews: PreviewProvider {
    static var previews: some View {
        KeepAwakeSettingView()
    }
}
