//
//  CleanProgressView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/8.
//

import SwiftUI

struct GaugeProgressStyle: ProgressViewStyle {
    var strokeColor = Color.green
    var strokeWidth = 2.0

    func makeBody(configuration: Configuration) -> some View {
        let fractionCompleted = configuration.fractionCompleted ?? 0

        return ZStack {
            Circle()
                .trim(from: 0, to: CGFloat(fractionCompleted))
                .stroke(strokeColor, style: StrokeStyle(lineWidth: CGFloat(strokeWidth), lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}


struct CleanProgressView: View {
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    @State private var progress = 0.0
    var body: some View {
        Circle().stroke(.blue.opacity(0.8), lineWidth: 4)
            .frame(width: 30, height: 30)
            .overlay(ProgressView(value: progress, total: 1.0)
                        .progressViewStyle(GaugeProgressStyle())
                        .contentShape(Rectangle()))
            .onReceive(timer) { _ in
                if let xcodeSwitch = SwitchManager.shared.getSwitch(of: .xcodeCache) as? XcodeCacheSwitch {
                    progress = xcodeSwitch.progressPercent
                }
                
            }
    }
}

struct CleanProgressView_Previews: PreviewProvider {
    static var previews: some View {
        CleanProgressView()
    }
}
