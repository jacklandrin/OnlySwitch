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
    @State var textColor: Color = .gray
    var ptswitch: PomodoroTimerSwitch
    var showImage: Bool = false

    var body: some View {
        HStack {
            if showImage && !leftTime.isEmpty {
                Image(systemName: "timer")
            }

            Text(leftTime)
                .foregroundColor(textColor)
                .onReceive(timer) { _ in
                    Task { @MainActor in
                        let info = await ptswitch.currentInfo()
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
        .animation(.snappy, value: leftTime)
    }
}

#if DEBUG
struct TimerCountDownView_Previews: PreviewProvider {
    static var previews: some View {
        TimerCountDownView(ptswitch: PomodoroTimerSwitch())
    }
}
#endif
