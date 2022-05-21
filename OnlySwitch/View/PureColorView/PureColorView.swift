//
//  PureColorView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/21.
//

import SwiftUI

struct PureColorView: View {
    @ObservedObject var vm = PureColorVM()
    @State var closeButtonAlpha = 1.0
    @State var isGuideHidden = false
    var body: some View {
        ZStack {
            VStack {
                HStack{
                    Spacer()
                    Button(action: {
                        Router.closeWindow(controller: Router.pureColorWindowController)
                        NotificationCenter.default.post(name: changeSettingNotification, object: nil)
                    }, label: {
                        Image(systemName: "x.circle")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                            .opacity(closeButtonAlpha)
                    })
                    .buttonStyle(.borderless)
                    .shadow(radius: 3)
                    .onHover(perform: { hover in
                        withAnimation {
                            closeButtonAlpha = hover ? 1.0 : 0.0
                            isGuideHidden = !hover
                        }
                    })
                    .padding(20)
                }
                Spacer()
            }
            ColorChangeGuide()
                .frame(width: 700, height: 700)
                .isHidden(isGuideHidden, remove: true)
        }.background(vm.currentColor)
            .onAppear{
                vm.startDetectKeyboard()
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    withAnimation {
                        closeButtonAlpha = 0.0
                        isGuideHidden = true
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
