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
    @Environment(\.colorScheme) private var colorScheme
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
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .padding(20)
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
                            Image(systemName: "gear")
                                .font(.system(size: 18))
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
            .frame(width: 800, height: 500)
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
