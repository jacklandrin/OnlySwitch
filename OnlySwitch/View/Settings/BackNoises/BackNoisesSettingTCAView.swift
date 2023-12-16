//
//  BackNoisesSettingTCAView.swift
//  OnlySwitch
//
//  Created by Leon on 2023/12/15.
//

import SwiftUI
import ComposableArchitecture

struct BackNoisesSettingTCAView: View {
    let store: StoreOf<BackNoisesSettingReducer>
    
    var body: some View {
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
    }
}

#Preview {
    BackNoisesSettingTCAView(
        store: Store(initialState: BackNoisesSettingReducer.State()) {
            BackNoisesSettingReducer()
        }
    )
}
