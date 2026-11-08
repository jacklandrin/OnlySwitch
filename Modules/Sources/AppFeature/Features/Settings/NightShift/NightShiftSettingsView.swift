//
//  NightShiftSettingsView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/6/19.
//

import SwiftUI

struct NightShiftSettingsView: View {
    @StateObject var vm = NightShiftSettingsVM()

    var body: some View {
        Form {
            // MARK: - Strength Section
            Section {
                HStack {
                    Text("Night Shift Strength".localized() + ":")
                    Spacer()
                    Slider(value: $vm.sliderValue)
                        .frame(width: 120)
                    Text("\(Int(vm.sliderValue * 100))%")
                        .frame(width: 40, alignment: .trailing)
                }
            } header: {
                Text("Strength".localized())
            }
            
            // MARK: - Schedule Section
            Section {
                Toggle("Daily Schedule:".localized(), isOn: $vm.isScheduleOn)
                
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
        }
        .formStyle(.grouped)
    }
}
