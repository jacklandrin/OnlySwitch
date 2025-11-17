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
        VStack(alignment: .leading, spacing: 40) {
            HStack {
                Text("Night Shift Strength".localized() + ":")
                Slider(value: $vm.sliderValue)
                    .frame(width: 120, height: 10)
                Text("\(Int(vm.sliderValue * 100))%")
                    .frame(width: 40, alignment: .leading)
            }

            VStack(alignment:.leading, spacing: 20) {
                HStack {
                    Toggle("", isOn: $vm.isScheduleOn)
                    Text("Daily Schedule:".localized())
                }

                DatePicker("from:".localized(),
                           selection: $vm.startDate,
                           displayedComponents: .hourAndMinute)
                .frame(width:190)

                HStack {
                    DatePicker("to:    ".localized(),
                               selection: $vm.endDate,
                               displayedComponents: .hourAndMinute)
                    .frame(width:190)

                    Text("Tomorrow".localized())
                        .foregroundColor(.green)
                        .isHidden(!vm.isTomorrow)
                }

            }.frame(height: 94)
        }
    }
}
