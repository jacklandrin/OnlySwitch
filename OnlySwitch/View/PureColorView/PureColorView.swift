//
//  PureColorView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/21.
//

import SwiftUI

struct PureColorView: View {
    @ObservedObject var vm = PureColorVM()

    var body: some View {
        ZStack {
            VStack {
                HStack{
                    Spacer()
                    Button(action: {
                        vm.exitScreenTestMode()
                    }, label: {
                        Image(systemName: "xmark.circle")
                            .font(.largeTitle)
                            .foregroundColor(vm.currentColor == .white ? .black : .white)
                            .opacity(vm.tipAlpha)
                    })
                    .buttonStyle(.borderless)
                    .shadow(radius: 3)
                    .onHover(perform: { hover in
                        withAnimation {
                            vm.isHovering = hover
                        }
                    })
                    .padding(20)
                }
                Spacer()
                Text("Keyboard Locked ↓".localized())
                    .fontWeight(.bold)
                    .font(.system(size: 30))
                    .foregroundColor(vm.currentColor == .white ? .black : .white)
                    .opacity(vm.tipAlpha)
                    .onHover(perform: { hover in
                        withAnimation {
                            vm.isHovering = hover
                        }
                    })
                    .padding(.bottom, 30)
            }
            ColorChangeGuide().environmentObject(vm)
                .frame(width: 700, height: 700)
                .opacity(vm.tipAlpha)
                .onHover(perform: { hover in
                    withAnimation {
                        vm.isHovering = hover
                    }
                })
        }.background(vm.currentColor)
            .onAppear{
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    withAnimation {
                        if !vm.isHovering {
                            vm.tipAlpha = 0.0
                        }
                    }
                }
                vm.forbiddenKeyboard()
            }
            .onDisappear{
                vm.recoverKeyboard()
            }
            .ignoresSafeArea()
    }
}

#if DEBUG
struct PureColorView_Previews: PreviewProvider {
    static var previews: some View {
        PureColorView()
    }
}
#endif
