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
        WithPerceptionTracking {
            Form {
                // MARK: - Brightness Section
                Section {
                    HStack {
                        Text("Brightness:".localized())
                        Spacer()
                        Slider(
                            value: Binding(
                                get: { store.brightness },
                                set: { store.send(.setBrightness($0)) }
                            )
                        )
                        .frame(width: 120)
                        Text("\(Int(store.brightness * 100))%")
                            .frame(width: 40, alignment: .trailing)
                    }
                    
                    Toggle(
                        "Adjust keyboard brightness in low light".localized(),
                        isOn: Binding(
                            get: { store.autoBrightness },
                            set: { store.send(.setAutoBrightness($0)) }
                        )
                    )
                } header: {
                    Text("Keyboard".localized())
                }
            }
            .formStyle(.grouped)
            .onAppear {
                store.send(.viewAppeared)
            }
        }
    }
}
