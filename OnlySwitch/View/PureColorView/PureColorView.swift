//
//  PureColorView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/21.
//

import SwiftUI

struct PureColorView: View {
    @ObservedObject var vm = PureColorVM()
    @State var tipAlpha = 1.0
    var body: some View {
        ZStack {
            VStack {
                HStack{
                    Spacer()
                    Button(action: {
                        Router.closeWindow(controller: Router.pureColorWindowController)
                        NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: SwitchType.screenTest)
                    }, label: {
                        Image(systemName: "x.circle")
                            .font(.largeTitle)
                            .foregroundColor(vm.currentColor == .white ? .black : .white)
                            .opacity(tipAlpha)
                    })
                    .buttonStyle(.borderless)
                    .shadow(radius: 3)
                    .onHover(perform: { hover in
                        withAnimation {
                            tipAlpha = hover ? 1.0 : 0.0
                        }
                    })
                    .padding(20)
                }
                Spacer()
            }
            ColorChangeGuide().environmentObject(vm)
                .frame(width: 700, height: 700)
                .opacity(tipAlpha)
                .onHover(perform: { hover in
                    withAnimation {
                        tipAlpha = hover ? 1.0 : 0.0
                    }
                })
        }.background(vm.currentColor)
            .onAppear{
                vm.startDetectKeyboard()
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    withAnimation {
                        tipAlpha = 0.0
                    }
                }
            }
    }
}

struct PureColorView_Previews: PreviewProvider {
    static var previews: some View {
        PureColorView()
    }
}
