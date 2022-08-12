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
        VStack(alignment:.leading, spacing: 20) {
            HStack {
                Toggle(isOn: $vm.scheduleMode) {
                    Text("")
                }.toggleStyle(.automatic)
                Text("Keep until after:")
                Menu(vm.converTimeDescription(duration: vm.currentDuration)) {
                    ForEach(vm.durationSet, id:\.self) { duration in
                        Button(vm.converTimeDescription(duration: duration)){
                            vm.currentDuration = duration
                        }
                    }
                }.frame(width:120, height: 30)
                
            }
            
            HStack {
                VStack(alignment:.leading) {
                    Toggle(isOn: $vm.afterMode) {
                        Text("")
                    }
                    Spacer()
                        .frame(height: 94)
                }
                
                
                VStack(alignment:.leading, spacing: 20) {
                    Text("Daily Schedule Keep Awake:")
                

                    DatePicker("from:",
                               selection: $vm.startDate,
                               displayedComponents: .hourAndMinute)
                    .frame(width:150)
                

                    DatePicker("to:    ",
                               selection: $vm.endDate,
                               displayedComponents: .hourAndMinute)
                    .frame(width:150)
                
                }.frame(height: 94)
                
            }
        }
    }
}

struct KeepAwakeSettingView_Previews: PreviewProvider {
    static var previews: some View {
        KeepAwakeSettingView()
    }
}
