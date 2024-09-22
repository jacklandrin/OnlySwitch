//
//  OnlyControlView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2024/8/27.
//

import ComposableArchitecture
import SwiftUI
import OnlyControl
import Defines
import Foundation

struct OnlyControlView: View {
    let store: StoreOf<OnlyControlReducer>

    init(store: StoreOf<OnlyControlReducer>) {
        self.store = store
    }

    @StateObject var switchVM = SwitchListVM()
    var body: some View {
        WithPerceptionTracking {
            ZStack {
                VisualEffectView(material: .popover, blendingMode: .behindWindow)
                VStack(spacing: 0) {
                    HStack {
                        Text(Date(), style: .time)
                            .font(.system(size: 60, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding()
                        Spacer()
                    }
                    Spacer()
                    DashboardView(store: store.scope(state: \.dashboard, action: \.dashboardAction))
                        .background(
                            // A tricky approach to prevent dragging window
                            Button{} label: {
                                Color.clear
                            }
                        )
                        .buttonStyle(.plain)
                    HStack {
                        Spacer()
                        Button(action: {
                            switchVM.showSettingsWindow()
                        }, label: {
                            Image(systemName: "gearshape.circle")
                                .font(.system(size: 17))
                        }).buttonStyle(.plain)
                            .padding(10)
                            .help(Text("Settings".localized()))
                    }
                }
            }
            .cornerRadius(15)
            .blur(radius: store.blurRadius)
            .opacity(store.opacity)
            .animation(.interactiveSpring(duration: 0.5), value: store.blurRadius)
            .frame(width: 800, height: 450)
            .ignoresSafeArea()
            .padding(10)
            .task {
                store.send(.task)
            }
        }
    }
}

#Preview {
    OnlyControlView(store: .init(initialState: .init()) {
        OnlyControlReducer()
    })
}

class OnlyControlWindow: NSWindow, NSWindowDelegate {
    override var canBecomeKey: Bool {
        true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
    }

}
