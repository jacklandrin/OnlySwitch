//
//  SwitchToggle.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/1.
//

import SwiftUI

struct SwitchToggle: View {
    @Binding var isOn:Bool
    var pressButton:(_ isOn:Bool) -> Void = {_ in}
    init(isOn:Binding<Bool>, pressButton:@escaping (_ isOn:Bool) -> Void) {
        self._isOn = isOn
        self.pressButton = pressButton
    }
    
    var body: some View {
        Button {
           pressButton(!isOn)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 15)
                    .modify { view in
                        if #available(macOS 13, *) {
                            view
                                .foregroundStyle(
                                    toggleColor(isOn: isOn)
                                        .shadow(
                                            .inner(
                                                radius: 2,
                                                x: 1,
                                                y: 1
                                            )
                                        )
                                )
                        } else {
                            view
                                .foregroundColor(toggleColor(isOn: isOn))
                        }
                    }
                    .frame(height: 30)
                Circle()
                    .frame(height: 26)
                    .offset(x: isOn ? 12 : -12)
                    .modify { view in
                        if #available(macOS 13, *) {
                            view
                                .foregroundStyle(
                                    .white
                                        .gradient
                                        .shadow(
                                            .drop(radius: 3, x: 1, y: 1)
                                        )
                                )
                        } else {
                            view
                                .foregroundColor(.white)
                                .shadow(radius: 3)
                        }
                    }
            }
        }
        .buttonStyle(.plain)
        .frame(width: 56, height: 30)
    }

    private func toggleColor(isOn: Bool) -> Color {
        isOn ? .accentColor : .gray.opacity(0.3)
    }
}

#if DEBUG
struct SwitchToggle_Previews: PreviewProvider {
    static var previews: some View {
        SwitchToggle(isOn: .constant(true), pressButton: {_ in})
    }
}
#endif
