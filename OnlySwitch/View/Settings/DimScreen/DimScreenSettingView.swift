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
        VStack(spacing:40) {
            HStack {
                Text("Dim Brightness To".localized() + ":")
                Slider(value: $vm.sliderValue)
                    .frame(width: 120, height: 10)
                Text("\(Int(vm.sliderValue * 100))%")
            }
            
            HStack {
                Text("Dim Screen After:".localized())
                Menu(vm.converTimeDescription(duration: vm.currentDuration)) {
                    ForEach(vm.durationSet, id:\.self) { duration in
                        Button(vm.converTimeDescription(duration: duration)){
                            vm.currentDuration = duration
                        }
                    }
                }.frame(width:150, height: 30)
            }
        }
        .navigationTitle("Dim Screen".localized())
    }
}

struct DimScreenSettingView_Previews: PreviewProvider {
    static var previews: some View {
        DimScreenSettingView()
    }
}
