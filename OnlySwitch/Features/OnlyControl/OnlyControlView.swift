//
//  OnlyControlView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2024/8/27.
//

import AppKit
import ComposableArchitecture
import SwiftUI
import OnlyControl
import Defines
import Foundation

struct OnlyControlView: View {
    @Environment(\.colorScheme) private var colorScheme
    let store: StoreOf<OnlyControlReducer>
    @ObservedObject private var playerItem = RadioStationSwitch.shared.playerItem

    init(store: StoreOf<OnlyControlReducer>) {
        self.store = store
    }

    var body: some View {
        WithPerceptionTracking {
            ZStack {
                VisualEffectView(material: .popover, blendingMode: .behindWindow)

                VStack {
                    Spacer()
                    BluredSoundWave(width: 800, height: 200)
                        .rotation3DEffect(.degrees(180), axis: (x: 1, y: 0, z: 0))
                        .opacity(0.9)
                        .isHidden(!store.soundWaveEffectDisplay || !playerItem.isPlaying, remove: true)
                }

                VStack(spacing: 0) {
                    Spacer()
                    HStack(alignment: .bottom) {
                        Text(Date(), style: .time)
                            .font(.system(size: 60, weight: .bold, design: .rounded))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .padding(.top, 30)
                            .padding(.horizontal, 30)

                        if store.isAirPodsConnected && !store.airPodsBatteryValues.isEmpty {
                            AirPodsBatteryView(batteryValues: store.airPodsBatteryValues)
                                .padding(.bottom, 16)
                                .padding(.leading, 40)
                        }

                        TimerCountDownView(ptswitch: PomodoroTimerSwitch.shared, showImage: true)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .padding(.bottom, 12)
                        Spacer()
                    }
                    Spacer()
                    DashboardView(store: store.scope(state: \.dashboard, action: \.dashboardAction))
                        .background(
                            // A tricky approach to prevent dragging window
                            Button{} label: {
                                Color.clear
                            }
                            .buttonStyle(.plain)
                        )

                    HStack {
                        Spacer()
                        if playerItem.streamInfo == "" {
                            HStack {
                                Text("Only Switch")
                                    .fontWeight(.bold)
                                    .padding(10)

                                Text("v\(SystemInfo.majorVersion as! String)")
                                    .offset(x:-10)
                            }
                            .transition(.move(edge: .bottom))

                        } else {
                            RollingText(
                                text: playerItem.streamInfo,
                                leftFade: 16,
                                rightFade: 16,
                                startDelay: 3
                            )
                            .frame(height:20)
                            .padding(10)
                            .transition(.move(edge: .bottom))
                        }

                        Spacer()
                        Button(action: {
                            store.send(.openSettings)
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

final class OnlyControlWindow: NSWindow, NSWindowDelegate {
    static let shared = OnlyControlWindow()

    var isShowing: Bool = false

    private let onlyControlStore: StoreOf<OnlyControlReducer> = .init(initialState: .init()) {
        OnlyControlReducer()
    }

    override var canBecomeKey: Bool {
        true
    }

    private init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        setupWindow()
    }

    private func setupWindow() {
        let view = NSHostingView(rootView: OnlyControlView(store: onlyControlStore))
        let contentRect = contentRect(forFrameRect: frame)
        view.frame = contentRect
        view.canDrawSubviewsIntoLayer = true
        contentView = view

        isMovable = true
        collectionBehavior = [.participatesInCycle, .canJoinAllSpaces, .fullScreenPrimary]
        level = .mainMenu
        ignoresMouseEvents = false
        hasShadow = true
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isMovableByWindowBackground = true
        isOpaque = false
        delegate = self

        makeKeyAndOrderFront(nil)
        center()
        setIsVisible(false)
    }

    func show() {
        makeKeyAndOrderFront(nil)
        setFrameUsingName("OnlyControlWindow")
        setFrameAutosaveName("OnlyControlWindow")
        isShowing = true
        onlyControlStore.send(.showControl)
    }

    func hide(completion: (() -> Void)? = nil) {
        onlyControlStore.send(.hideControl)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.51) { [weak self] in
            guard let self else { return }
            self.close()
            self.isShowing = false
            completion?()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
    }
}
