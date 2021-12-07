//
//  AirPodsBatteryView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/7.
//

import SwiftUI

struct AirPodsBatteryView: View {
    var batteryValues:[Float]
    @State var batteryText = ["L","R","C"]
    private let viewWidth = 24.0
    private let viewHeight = 10.0
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        HStack(spacing:8) {
            ForEach(batteryValues.indices, id:\.self) { index in
                HStack(spacing:4) {
                    
                    ZStack{
                        Circle()
                            .foregroundColor(.gray)
                            .frame(width: 10, height: 10)
                        Text(batteryText[index])
                            .font(.system(size:7))
                    }
                    
                    
                    HStack {
                        Rectangle()
                            .foregroundColor(batteryValues[index] < 0.2 ? .red : .green)
                            .frame(width: CGFloat(batteryValues[index]) * viewWidth, height: viewHeight)
                        Spacer()
                            .frame(width: ((1.0 - CGFloat(batteryValues[index])) * viewWidth))
                    }.frame(width: viewWidth, height: viewHeight)
                  .overlay(RoundedRectangle(cornerRadius: 2).stroke(colorScheme == .dark ? .white : .black, lineWidth: 1))
                  .overlay(Text("\(Int(batteryValues[index] * 100))%")
                            .font(.system(size:6)).fontWeight(.medium))
                }
                
            }
        }.frame(width:viewWidth)
    }
}

struct AirPodsBatteryView_Previews: PreviewProvider {
    static var previews: some View {
        AirPodsBatteryView(batteryValues: [0.5,0.15,1]).frame(width: 140, height: 20)
    }
}
