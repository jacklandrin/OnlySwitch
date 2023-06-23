//
//  EvolutionBarView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/6/15.
//

import SwiftUI

struct EvolutionBarView: View {

    @EnvironmentObject var evolutionBarVM: EvolutionBarVM

    var body: some View {
        Image(
            systemName: evolutionBarVM.iconName ??
            (evolutionBarVM.controlType == .Switch
             ? "lightswitch.on.square"
             : "button.programmable.square.fill")
        )
        .renderingMode(.template)
        .resizable()
        .scaledToFit()
        .frame(width: 25, height: 25)
        .padding(.trailing, 8)

        Text(evolutionBarVM.barName)
            .frame(alignment: .leading)

        Spacer()

        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(.small)
            .isHidden(!evolutionBarVM.processing, remove: true)

        switch evolutionBarVM.controlType {
            case .Switch:
                SwitchToggle(isOn: $evolutionBarVM.isOn) { isOn in
                    evolutionBarVM.doSwitch(isOn: isOn)
                }
                .disabled(evolutionBarVM.processing)
                .animation(.spring(), value: evolutionBarVM.isOn)
                .scaleEffect(0.8)

            case .Button:
                Button(action: {
                    evolutionBarVM.doSwitch(isOn: true)
                }, label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15)
                            .foregroundColor(.accentColor)
                            .frame(height:26)
                        Text("Run".localized())
                            .font(.system(size: "Run".localized().count > 6 ? 300 : 12))
                            .lineLimit(1)
                            .minimumScaleFactor(0.02)
                            .foregroundColor(.white)
                    }.frame(width: 46, height: 30)
                })
                .buttonStyle(.plain)
                .shadow(radius: 2)
                .padding(.horizontal, 6)

            default:
                EmptyView()
        }
    }
}
