//
//  RadioSetting.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/9.
//

import SwiftUI
import AlertToast

struct RadioSettingView: View {

    @StateObject var radioSettingVM = RadioSettingVM()
    @State var updateTable:UUID = UUID()

    
    var body: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment:.leading) {
                    
                    Toggle("Sound Wave Effect".localized(), isOn: $radioSettingVM.soundWaveEffectDisplay)
                    
                    HStack {
                        Text("Allow Notification:".localized())
                        Toggle("Changing Station".localized(), isOn: $radioSettingVM.allowNotificationChangingStation)
                        Toggle("Soundtrack".localized(), isOn: $radioSettingVM.allowNotificationTrack)
                    }.frame(height:30)
                }
                
                Spacer()
                
                VStack(alignment:.trailing) {
                    HStack {
                        Text("Volume".localized() + ":")
                        Slider(value: $radioSettingVM.sliderValue)
                            .frame(width: 150, height: 10)
                    }
                    HStack {
                        Button(action: {
                            radioSettingVM.isTipPopover = true
                        }){
                            Image(systemName: "questionmark.circle")
                        }.popover(isPresented: $radioSettingVM.isTipPopover,
                                  arrowEdge: .bottom) {
                            Text("The radio stations can be imported and exported as a Json file. The keys are \"name\" and \"url\".".localized())
                                .frame(width: 130)
                                .padding()
                        }
                            .buttonStyle(PlainButtonStyle())
                        
                        Button(action: {
                            radioSettingVM.importList()
                        }, label: {
                            Text("Import".localized())
                        })
                        
                        Button(action: {
                            radioSettingVM.exportList()
                        }, label: {
                            Text("Export".localized())
                        })
                        
                    }.frame(height:30)
                    
                } .padding(.trailing, 10)
                
            }
                .padding(.top, 10)
                .padding(.leading, 10)
            Divider()
            Table($radioSettingVM.radioList,
                  selection: $radioSettingVM.selectRow) {
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
                                radioSettingVM.objectWillChange.send()
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
                                radioSettingVM.objectWillChange.send()
                            }.allowsHitTesting(row.id == radioSettingVM.selectRow)
                    }
                }
            }
                
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
        }.navigationTitle(Text("Radio".localized()))
            .toast(isPresenting: $radioSettingVM.showErrorToast) {
                AlertToast(displayMode: .alert,
                           type: .error(.red),
                           title: radioSettingVM.errorInfo.localized())
            }
            .toast(isPresenting: $radioSettingVM.showSuccessToast) {
                AlertToast(displayMode: .alert,
                           type: .complete(.green),
                           title: radioSettingVM.successInfo.localized())
            }
    }
}

#if DEBUG
struct RadioSetting_Previews: PreviewProvider {
    static var previews: some View {
        RadioSettingView()
    }
}
#endif
