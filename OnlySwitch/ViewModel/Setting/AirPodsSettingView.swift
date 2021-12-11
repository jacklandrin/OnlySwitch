//
//  AirPodsSettingView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/11.
//

import SwiftUI

struct AirPodsSettingView: View {
    @ObservedObject var airPodsSettingVM = AirPodsSettingVM()
    @State var updateID = UUID()
    var body: some View {
        List{
            Section(header:Text("AirPods")) {
                ForEach(airPodsSettingVM.airPodsList.indices, id:\.self) { index in
                    Button(action: {
                        airPodsSettingVM.select(item: airPodsSettingVM.airPodsList[index])
                        updateID = UUID()
                    }, label: {
                        HStack{
                            Text(airPodsSettingVM.airPodsList[index].name)
                                .frame(width:200, alignment: .leading)
                                .padding(.horizontal, 6)
                            Rectangle()
                                .frame(width: 1, height: 22)
                                .foregroundColor(.gray)
                            Text(airPodsSettingVM.airPodsList[index].address)
                                .frame(width: 300, alignment: .leading)
                                .padding(.horizontal, 4)
                        }.background(backgroundColor(item: airPodsSettingVM.airPodsList[index]).opacity(0.35))
                            .cornerRadius(3)
                    }).buttonStyle(.plain)
                }
            }
        }.id(updateID)
    }
    
    func backgroundColor(item:AirPodsItem) -> Color {
        guard let device = AirPodsSwitch.shared.currentDevice else {return Color(nsColor: NSColor.lightGray)}
        if device.addressString == item.address {
            return .blue
        } else {
            return Color(nsColor: NSColor.lightGray)
        }
    }
}

struct AirPodsSettingView_Previews: PreviewProvider {
    static var previews: some View {
        AirPodsSettingView()
    }
}
