//
//  EvolutionEditorView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/27.
//

import AlertToast
import ComposableArchitecture
import SwiftUI

@available(macOS 13.0, *)
struct EvolutionEditorView: View {
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    let store: StoreOf<EvolutionEditorReducer>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack {
                HStack {
                    Text("Name:".localized())
                    TextField("",
                              text: viewStore.binding(
                                get: { $0.evolution.name },
                                send: { .changeName($0) }
                              )
                    )
                    Spacer()
                    Text("Icon:".localized())
                    Image(
                        systemName: viewStore.evolution.iconName ??
                        (
                            viewStore.evolution.controlType == .Switch
                            ? "lightswitch.on.square"
                            : "button.programmable.square.fill"
                        )
                    )
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .onTapGesture {
                        viewStore.send(.toggleIconNamesPopover(!viewStore.showIconNamesPopover))
                    }
                    .popover(
                        isPresented: viewStore.binding(
                            get: { $0.showIconNamesPopover },
                            send: { .toggleIconNamesPopover($0) }
                        )
                    ) {
                        ScrollView(.vertical) {
                            LazyVGrid(columns: columns, spacing: 4) {
                                ForEach(EvolutionEditorView.iconNames, id: \.self) { name in
                                    Button(
                                        action: {
                                            viewStore.send(.selectIcon(name))
                                        }
                                    ) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 10)
                                                .foregroundColor(iconBackground(viewStore: viewStore, name: name))
                                                .frame(width: 30, height: 30)

                                            Image(systemName: name)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 26, height: 26)
                                        }

                                    }
                                    .buttonStyle(.plain)
                                    .background(iconBackground(viewStore: viewStore, name: name))
                                }
                            }
                            .frame(width: 150)
                            .padding()
                        }
                        .frame(height: 170)
                    }
                }

                Picker("",
                       selection: viewStore.binding(
                        get: { $0.evolution.controlType },
                        send: { .changeType($0) }
                       )
                ) {
                    Text("Switch".localized()).tag(ControlType.Switch)
                    Text("Button".localized()).tag(ControlType.Button)
                }
                .pickerStyle(.segmented)

                ScrollView(.vertical) {
                    VStack {
                        ForEachStore(
                            store.scope(
                                state: \.commandStates,
                                action: EvolutionEditorReducer.Action.commandAction(id:action:)
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
                        viewStore.send(.save)
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
                isPresenting: viewStore.binding(
                    get: { $0.showError },
                    send: { .errorControl($0) }
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

    func iconBackground(viewStore: ViewStore<EvolutionEditorReducer.State, EvolutionEditorReducer.Action>, name: String) -> Color {
        guard let currentIconName = viewStore.evolution.iconName else {
            if (viewStore.evolution.controlType == .Button &&
                name == "button.programmable.square.fill") ||
                (viewStore.evolution.controlType == .Switch &&
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

@available(macOS 13.0, *)
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

@available(macOS 13.0, *)
struct EvolutionEditorView_Previews: PreviewProvider {
    static var previews: some View {
        EvolutionEditorView(
            store: Store(initialState: EvolutionEditorReducer.State()) {
                EvolutionEditorReducer()
            }
        )
    }
}
