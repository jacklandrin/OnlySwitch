//
//  BackNoisesSettingView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/11.
//

import SwiftUI

struct BackNoisesSettingView: View {
    
    @StateObject var backNoisesSettingVM = BackNoisesSettingVM()
    
    var body: some View {
        VStack {
            List{
                Section(header: Text("Back Noises")) {
                    ForEach(backNoisesSettingVM.trackList.indices, id:\.self) { index in
                        Button(action: {
                            backNoisesSettingVM.selectTrack(index: index)
                        }, label: {
                            HStack {
                                Text(backNoisesSettingVM.trackList[index])
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                Spacer()
                            }
                        }).buttonStyle(.plain)
                            .background(backNoisesSettingVM.trackList[index] == backNoisesSettingVM.currentTrack ? Color.blue : Color.clear)
                    }
                }
            }
            
            HStack {
                Text("Stop after:")
                Menu(backNoisesSettingVM.converTimeDescription(duration: backNoisesSettingVM.automaticallyStopPlayNoise)) {
                    ForEach(backNoisesSettingVM.durationSet, id:\.self) { duration in
                        Button(backNoisesSettingVM.converTimeDescription(duration: duration)){
                            backNoisesSettingVM.automaticallyStopPlayNoise = duration
                        }
                    }
                }.frame(width:150, height: 30)
                Spacer()
            }.padding()
        }
    }
}

struct BackNoisesSettingView_Previews: PreviewProvider {
    static var previews: some View {
        BackNoisesSettingView()
    }
}
