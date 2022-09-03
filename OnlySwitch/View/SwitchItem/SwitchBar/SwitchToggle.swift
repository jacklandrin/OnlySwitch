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
        Button(action: {
           pressButton(!isOn)
        }, label: {
            ZStack {
                RoundedRectangle(cornerRadius: 15)
                    .foregroundColor(isOn ? .accentColor : .gray.opacity(0.3))
                    .frame(height:30)
                    
                Circle()
                    .foregroundColor(.white)
                    .frame(height:26)
                    .offset(x:isOn ? 12 : -12)
                    .shadow(radius: 3)
            }
        }).buttonStyle(.plain)
            .frame(width: 56, height: 30)
        
    }
}

#if DEBUG
struct SwitchToggle_Previews: PreviewProvider {
    static var previews: some View {
        SwitchToggle(isOn: .constant(true), pressButton: {_ in})
    }
}
#endif
