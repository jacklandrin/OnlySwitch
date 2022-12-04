//
//  UpdateView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/9.
//

import SwiftUI

struct UpdateView: View {
    @ObservedObject var updateVM:UpdateVM

    init(presenter:GitHubPresenter, updateWindow:NSWindow?) {
        self.updateVM = UpdateVM(presenter: presenter)
        self.updateWindow = updateWindow
    }
    
    let updateWindow:NSWindow?
    var body: some View {
        VStack {
            Image("only_switch")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .padding(.top, 20)
            
            Text("Update".localized())
                .font(.system(size: 16))
                .fontWeight(.bold)
                .padding()
            
            Text("You can update to new version. The latest version is v%@".localizeWithFormat(arguments: updateVM.latestVersion))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
                .padding(.bottom)
            HStack {
                Button(action: {
                    updateWindow?.close()
                }, label: {
                    Text("Cancel".localized())
                        .font(.system(size: 15))
                        .fontWeight(.bold)
                        .frame(width: 120, height: 40)
                        .foregroundColor(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .foregroundColor(Color(nsColor: .darkGray))
                        )
                })
                .buttonStyle(.plain)
                
                Spacer()
                Button(action: {
                    updateVM.downloadDMG()
                }, label: {
                    Text("Download".localized())
                        .font(.system(size: 15))
                        .fontWeight(.bold)
                        .frame(width: 120, height: 40)
                        .foregroundColor(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .foregroundColor(Color(nsColor: AppColor.themeBlue))
                        )
                })
                .buttonStyle(.plain)
                    
            }.padding(.bottom, 20)
                .padding(.horizontal,  30)
        }
    }
}

struct UpdateView_Previews: PreviewProvider {
    static var previews: some View {
        UpdateView(presenter:GitHubPresenter(),
                   updateWindow: nil)
            .previewLayout(.fixed(width: 300, height: 130))
    }
}
