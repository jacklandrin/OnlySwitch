//
//  EvolutionCommandEditingView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/29.
//

import ComposableArchitecture
import SwiftUI

struct EvolutionCommandEditingView: View {

    let store: StoreOf<EvolutionCommandEditingReducer>
    
    var body: some View {
        WithPerceptionTracking {
            VStack(alignment: .leading) {
                HStack {
                    Text(store.command.commandType.typeTitle)
                        .fontWeight(.heavy)
                        .padding(.trailing, 20)

                    Picker("",
                           selection: Binding(
                            get: { store.command.executeType },
                            set: { store.send(.changeExecuteType($0)) }
                           )
                    ) {
                        Text("Shell").tag(CommandExecuteType.shell)
                        Text("Apple Script").tag(CommandExecuteType.applescript)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }

                TextField("",
                    text: Binding(
                        get: { store.command.commandString },
                        set: { store.send(.editCommand($0)) }
                    ),
                          axis: .vertical
                )
                .onSubmit {
                    store.send(.returnCommandString)
                }
                .multilineTextAlignment(.leading)
                .lineLimit(5...100)
                .frame(maxHeight: 300)

                HStack {
                    Button {
                        store.send(.shouldTest)
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .frame(width: 26, height: 26)
                    .help(Text("Debug".localized()))

                    Spacer().frame(width: 10)

                    if store.command.debugStatus == .failed {
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .frame(width: 22, height: 22)
                            .foregroundColor(Color.red)
                    } else if store.command.debugStatus == .success {
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .frame(width: 22, height: 22)
                            .foregroundColor(Color.green)
                    }
                    Spacer()
                }

                if store.command.commandType == .status {
                    HStack {
                        Text("Output:".localized())
                        Text(store.statusCommandResult)
                            .foregroundColor(.green)
                    }
                    TextField("True Condition".localized(), text: Binding(
                        get: { store.command.trueCondition ?? "" },
                        set: { store.send(.editTrueCondition($0)) }
                    ))
                }
            }
            
        }
    }
}

struct EvolutionCommandEditingView_Previews: PreviewProvider {
    static var previews: some View {
        EvolutionCommandEditingView(
            store: Store(
                initialState: EvolutionCommandEditingReducer.State(type: .on, command: nil))
            {
                EvolutionCommandEditingReducer()
            }
        )
    }
}
