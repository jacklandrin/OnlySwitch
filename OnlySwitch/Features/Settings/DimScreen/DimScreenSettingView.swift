//
//  DimScreenSettingView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/13.
//

import SwiftUI

struct DimScreenSettingView: View {
    @StateObject var vm = DimScreenSettingVM()
    
    var body: some View {
        Form {
            // MARK: - Brightness Section
            Section {
                HStack {
                    Text("Dim Brightness To".localized() + ":")
                    Spacer()
                    Slider(value: $vm.sliderValue)
                        .frame(width: 120)
                    Text("\(Int(vm.sliderValue * 100))%")
                        .frame(width: 40, alignment: .trailing)
                }
                
                Picker("Dim Screen After:".localized(), selection: $vm.currentDuration) {
                    ForEach(vm.durationSet, id: \.self) { duration in
                        Text(vm.converTimeDescription(duration: duration)).tag(duration)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Brightness".localized())
            }

            // MARK: - External Displays Section
            Section {
                Toggle(isOn: $vm.syncExternalBrightness) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sync external monitors".localized())
                        Text("External monitors follow the built-in display's brightness (F1/F2) via DDC/CI.".localized())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("External Displays".localized())
            }
        }
        .formStyle(.grouped)
    }
}

struct DimScreenSettingView_Previews: PreviewProvider {
    static var previews: some View {
        DimScreenSettingView()
    }
}
