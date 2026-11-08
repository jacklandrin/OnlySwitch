//
//  EvolutionEditorView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import AlertToast
import ComposableArchitecture
import SwiftUI
import Switches

struct EvolutionEditorView: View {
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    let store: StoreOf<EvolutionEditorReducer>

    var body: some View {
        WithPerceptionTracking {
            VStack {
                HStack {
                    Text("Name:".localized())
                    TextField("",
                              text: Binding(
                                get: { store.evolution.name },
                                set: { store.send(.changeName($0)) }
                              )
                    )
                    Spacer()
                    Text("Icon:".localized())
                    Image(
                        systemName: store.evolution.iconName ??
                        (
                            store.evolution.controlType == .Switch
                            ? "lightswitch.on.square"
                            : "button.programmable.square.fill"
                        )
                    )
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .onTapGesture {
                        store.send(.toggleIconNamesPopover(!store.showIconNamesPopover))
                    }
                    .popover(
                        isPresented: Binding(
                            get: { store.showIconNamesPopover },
                            set: { store.send(.toggleIconNamesPopover($0)) }
                        )
                    ) {
                        ScrollView(.vertical) {
                            LazyVGrid(columns: columns, spacing: 4) {
                                ForEach(EvolutionEditorView.iconNames, id: \.self) { name in
                                    Button(
                                        action: {
                                            store.send(.selectIcon(name))
                                        }
                                    ) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 10)
                                                .foregroundColor(iconBackground(name: name))
                                                .frame(width: 30, height: 30)

                                            Image(systemName: name)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 26, height: 26)
                                        }

                                    }
                                    .buttonStyle(.plain)
                                    .background(iconBackground(name: name))
                                }
                            }
                            .frame(width: 150)
                            .padding()
                        }
                        .frame(height: 170)
                    }
                }

                Picker("",
                       selection: Binding(
                        get: { store.evolution.controlType },
                        set: { store.send(.changeType($0)) }
                       )
                ) {
                    Text("Switch".localized()).tag(ControlType.Switch)
                    Text("Button".localized()).tag(ControlType.Button)
                }
                .pickerStyle(.segmented)

                ScrollView(.vertical) {
                    VStack {
                        ForEach(
                            store.scope(
                                state: \.commandStates,
                                action: \.commandAction
                            ),
                            content: { item in
                                EvolutionCommandEditingView(store: item)
                            }
                        )
                    }
                }

                HStack {
                    Spacer()
                    Text("Can be saved after passing all tests".localized())
                    Button(action: {
                        store.send(.save)
                    }) {
                        Text("Save".localized())
                    }
                }

            }
            .padding(10)
            .navigationTitle("Evolution Editor".localized())
            .onAppear{

            }
            .toast(
                isPresenting: Binding(
                    get: { store.showError },
                    set: { store.send(.errorControl($0)) }
                ),
                alert: {
                    AlertToast(
                        displayMode: .alert,
                        type: .error(.red),
                        title: "Save commands failed.".localized()
                    )
                }
            )
        }
    }

    func iconBackground(name: String) -> Color {
        guard let currentIconName = store.evolution.iconName else {
            if (store.evolution.controlType == .Button &&
                name == "button.programmable.square.fill") ||
                (store.evolution.controlType == .Switch &&
                name == "lightswitch.on.square") {
                return .accentColor
            } else {
                return .clear
            }
        }

        if currentIconName == name {
            return .accentColor
        } else {
            return .clear
        }
    }
}

extension EvolutionEditorView {
    static let iconNames = [
        "lightswitch.on.square",
        "button.programmable.square.fill",
        "externaldrive.fill.badge.timemachine",
        "moon.circle",
        "calendar.badge.clock",
        "person.crop.circle.badge.clock",
        "wand.and.rays.inverse",
        "slider.horizontal.3",
        "slider.horizontal.2.square.on.square",
        "slider.vertical.3",
        "power.circle",
        "keyboard",
        "globe",
        "sun.max.circle",
        "bag.circle",
        "creditcard",
        "dollarsign.circle",
        "hourglass.circle",
        "heart.circle",
        "cross.circle",
        "pill.circle",
        "location.circle",
        "arrow.up.arrow.down.circle",
        "arrow.left.arrow.right.circle",
        "arrowtriangle.forward.circle",
        "pause.circle",
        "stop.circle",
        "plus",
        "house",
        "lightbulb.circle",
        "balloon.2",
        "party.popper",
        "person.circle",
        "rectangle.badge.person.crop",
        "shield.lefthalf.filled",
        "lock",
        "lock.open",
        "key",
        "captions.bubble",
        "hare.fill",
        "tortoise.fill",
        "textformat.size",
        "minus.plus.batteryblock",
        "airplane.circle",
        "bolt.horizontal.circle",
        "network",
        "personalhotspot.circle",
        "antenna.radiowaves.left.and.right.circle",
        "externaldrive.connected.to.line.below",
        "wifi.circle",
        "gamecontroller",
        "squares.leading.rectangle",
        "arrow.clockwise.circle",
        "desktopcomputer"
    ]
}

struct EvolutionEditorView_Previews: PreviewProvider {
    static var previews: some View {
        EvolutionEditorView(
            store: Store(initialState: EvolutionEditorReducer.State()) {
                EvolutionEditorReducer()
            }
        )
    }
}
