//
//  TimerCountDownView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/26.
//

import SwiftUI

struct TimerCountDownView: View {
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State var leftTime = ""
    @State var textColor:Color = .gray
    var ptswitch:PomodoroTimerSwitch
    
    
    var body: some View {
        Text(leftTime)
            .foregroundColor(textColor)
            .onReceive(timer) { _ in
                let info = ptswitch.currentInfo()
                if info.isEmpty {
                    leftTime = ""
                } else {
                    let infoArray = info.split(separator: "-")
                    let status = PomodoroTimerSwitch.Status(rawValue: String(infoArray[0]))
                    leftTime = String(infoArray[1])
                    if status == .rest {
                        textColor = .green
                    } else {
                        textColor = .blue
                    }
                }
            }
    }
}

struct TimerCountDownView_Previews: PreviewProvider {
    static var previews: some View {
        TimerCountDownView(ptswitch: PomodoroTimerSwitch())
    }
}
