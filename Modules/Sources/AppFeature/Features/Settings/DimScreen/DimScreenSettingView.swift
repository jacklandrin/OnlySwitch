//
//  DimScreenSettingView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/13.
//

import SwiftUI
import DisplayBrightness

struct DimScreenSettingView: View {
    @StateObject var vm = DimScreenSettingVM()
    
    var body: some View {
        Form {
            Section {
                Toggle("Display Brightness".localized(), isOn: $vm.isDisplayBrightnessEnabled)
            } footer: {
                Text("Turn off to stop all brightness control, including the Brightness tab, brightness keys, remote brightness and Dim Screen.".localized())
            }

            if vm.isDisplayBrightnessEnabled {
                brightnessSections
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var brightnessSections: some View {
        Section {
            Toggle("Control External Displays via DDC".localized(), isOn: $vm.isExternalDisplayDDCEnabled)
        } footer: {
            Text("Adjusts external monitor brightness over DDC. When off, external displays use software dimming. Some monitors may disconnect or flicker with DDC.".localized())
        }

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
            Text("Dim Screen".localized())
        }

        DisplayBrightnessSettingsView(store: SettingsVM.shared.brightnessStore)
    }
}

struct DimScreenSettingView_Previews: PreviewProvider {
    static var previews: some View {
        DimScreenSettingView()
    }
}
