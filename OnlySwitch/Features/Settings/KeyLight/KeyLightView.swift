//
//  KeyLightView.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2024/4/2.
//

import ComposableArchitecture
import SwiftUI

struct KeyLightView: View {
    let store: StoreOf<KeyLightFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(alignment: .leading, spacing: 40) {
                HStack {
                    Text("Brightness:".localized())
                    Slider(
                        value: viewStore.binding(
                            get: { _ in viewStore.brightness},
                            send: { .setBrightness($0) }
                        )
                    )
                    .frame(width: 120, height: 10)
                    Text("\(Int(viewStore.brightness * 100))%")
                }
                Toggle(
                    isOn: viewStore.binding(
                        get: { _ in viewStore.autoBrightness },
                        send: { .setAutoBrightness($0) }
                    ),
                    label: { Text("Adjust keyboard brightness in low light".localized()) }
                )
            }
            .onAppear {
                viewStore.send(.viewAppeared)
            }
        }
    }
}
