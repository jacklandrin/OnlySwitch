//
//  EvolutionCommandEditingView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/5/29.
//

import ComposableArchitecture
import SwiftUI

@available(macOS 13.0, *)
struct EvolutionCommandEditingView: View {

    let store: StoreOf<EvolutionCommandEditingReducer>
    
    var body: some View {
        WithViewStore(self.store, observe: { $0 }) { viewStore in
            VStack(alignment: .leading) {
                HStack {
                    Text(viewStore.command.commandType.typeTitle)
                        .fontWeight(.heavy)
                        .padding(.trailing, 20)

                    Picker("",
                           selection: viewStore.binding(
                            get: { $0.command.executeType },
                            send: { .changeExecuteType($0) }
                           )
                    ) {
                        Text("Shell").tag(CommandExecuteType.shell)
                        Text("Apple Script").tag(CommandExecuteType.applescript)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }

                TextField("",
                    text: viewStore.binding(
                        get: { $0.command.commandString },
                        send: { .editCommand($0) }
                    ),
                          axis: .vertical
                )
                .onSubmit {
                    viewStore.send(.returnCommandString)
                }
                .multilineTextAlignment(.leading)
                .lineLimit(5...100)
                .frame(maxHeight: 300)

                HStack {
                    Button(action: {
                        viewStore.send(.shouldTest)
                    }) {
                        Image(systemName: "play.fill")
                    }
                    .frame(width: 26, height: 26)
                    .help(Text("Debug"))

                    Spacer().frame(width: 10)

                    if viewStore.command.debugStatus == .failed {
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .frame(width: 22, height: 22)
                            .foregroundColor(Color.red)
                    } else if viewStore.command.debugStatus == .success {
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .frame(width: 22, height: 22)
                            .foregroundColor(Color.green)
                    }
                    Spacer()
                }

                if viewStore.command.commandType == .status {
                    Text("Output:\(viewStore.statusCommandResult)")
                    TextField("True Condition".localized(), text: viewStore.binding(
                        get: { $0.command.trueCondition ?? "" },
                        send: { .editTrueCondition($0) }
                    ))
                }
            }
            
        }
    }
}

@available(macOS 13.3, *)
struct EvolutionCommandEditingView_Previews: PreviewProvider {
    static var previews: some View {
        EvolutionCommandEditingView(
            store: Store(
                initialState: EvolutionCommandEditingReducer.State(type: .on, command: nil),
                reducer: EvolutionCommandEditingReducer()
            )
        )
    }
}
