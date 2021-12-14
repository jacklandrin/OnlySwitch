//
//  RadioSetting.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/9.
//

import SwiftUI
import AlertToast

struct RadioSettingView: View {

    @ObservedObject var radioSettingVM = RadioSettingVM()
    @State var updateTable:UUID = UUID()
    var body: some View {
        VStack {
            Table($radioSettingVM.radioList, selection: $radioSettingVM.selectRow) {
                TableColumn("Name".localized()) { $row in
                    if row.isEditing {
                        TextEditor(text: $row.title)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .background(Color.clear)
                            .padding(0)
                            .overlay(Rectangle().stroke(.blue,lineWidth: 2))
                            
                    } else {
                        Text(row.title)
                            .onTapGesture {
                                guard row.id == radioSettingVM.selectRow else {return}
                                radioSettingVM.endEditing()
                                row.isEditing = true
                                updateTable = UUID()
                            }.allowsHitTesting(row.id == radioSettingVM.selectRow)
                    }
                }
                    .width(min: 50, ideal: 100, max: 200)
                TableColumn("Stream URL".localized()) { $row in
                    if row.isEditing {
                        TextEditor(text: $row.streamUrl)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .background(Color.clear)
                            .padding(0)
                            .overlay(Rectangle().stroke(.blue,lineWidth: 2))
                    } else {
                        Text(row.streamUrl)
                            .onTapGesture {
                                guard row.id == radioSettingVM.selectRow else {return}
                                radioSettingVM.endEditing()
                                row.isEditing = true
                                updateTable = UUID()
                            }.allowsHitTesting(row.id == radioSettingVM.selectRow)
                    }
                }
            }.id(updateTable)
                
            HStack {
                Button(action: {
                    radioSettingVM.selectStation()
                }, label: {
                    Text("Select".localized())
                })
                Text("Current: %@".localizeWithFormat(arguments: radioSettingVM.currentTitle))
                Spacer()
                Button(action: {
                    print("plus item")
                    radioSettingVM.addStation()
                }, label: {
                    Image(systemName: "plus")
                })
                    .contentShape(Rectangle())
                Button(action: {
                    print(radioSettingVM.selectRow ?? "nil")
                    radioSettingVM.deleteStation()
                }, label: {
                    Image(systemName: "minus")
                })
                    .contentShape(Rectangle())
            }.padding(10)
        }.navigationTitle(Text("Radio Stations"))
            .toast(isPresenting: $radioSettingVM.showErrorToast) {
                AlertToast(displayMode: .alert, type: .error(.red), title: radioSettingVM.errorInfo)
            }
    }
}


struct RadioSetting_Previews: PreviewProvider {
    static var previews: some View {
        RadioSettingView()
    }
}
