//
//  DashboardView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2024/7/7.
//

import ComposableArchitecture
import Defines
import SwiftUI

public struct DashboardView: View {
    let data = (1...20).map { ControlItemReducer.preview(id: $0) }
    let columns = [
            GridItem(.adaptive(minimum: 80))
        ]
    public init() {}

    public var body: some View {
        ScrollView {
            LazyVGrid(columns: columns) {
                ForEach(data, id: \.id) { item in
                    ControlItemView(store: Store(initialState: item) {
                        ControlItemReducer()
                    })
                }
            }
            .padding()
        }
        .frame(
            width: Layout.settingWindowWidth,
            height: Layout.settingWindowHeight
        )
    }
}

#Preview {
    DashboardView()
}
