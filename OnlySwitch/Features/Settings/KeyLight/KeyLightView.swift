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
            Form {
                // MARK: - Brightness Section
                Section {
                    HStack {
                        Text("Brightness:".localized())
                        Spacer()
                        Slider(
                            value: viewStore.binding(
                                get: { _ in viewStore.brightness },
                                send: { .setBrightness($0) }
                            )
                        )
                        .frame(width: 120)
                        Text("\(Int(viewStore.brightness * 100))%")
                            .frame(width: 40, alignment: .trailing)
                    }
                    
                    Toggle(
                        "Adjust keyboard brightness in low light".localized(),
                        isOn: viewStore.binding(
                            get: { _ in viewStore.autoBrightness },
                            send: { .setAutoBrightness($0) }
                        )
                    )
                } header: {
                    Text("Keyboard".localized())
                }
            }
            .formStyle(.grouped)
            .onAppear {
                viewStore.send(.viewAppeared)
            }
        }
    }
}
