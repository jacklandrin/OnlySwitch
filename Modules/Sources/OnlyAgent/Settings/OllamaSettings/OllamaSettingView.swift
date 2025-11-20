//
//  OllamaSettingView.swift
//  Modules
//
//  Created by Bo Liu on 18.11.25.
//

import ComposableArchitecture
import SwiftUI

@available(macOS 26.0, *)
public struct OllamaSettingView: View {
    @Perception.Bindable var store: StoreOf<OllamaSettingReducer>
    
    public init(store: StoreOf<OllamaSettingReducer>) {
        self.store = store
    }
    
    public var body: some View {
        WithPerceptionTracking {
            ScrollView {
                VStack {
                    HStack {
                        Text("API Host:")
                        Spacer()
                    }
                    TextField("", text: $store.host)
                        .padding(.bottom, 10)
                    HStack {
                        Text("Models:")
                        Spacer()
                        Button {
                            store.send(.refresh)
                        } label: {
                            Image(systemName: "arrow.clockwise.circle")
                        }
                        .buttonStyle(.plain)
                    }
                    
                    ForEach(store.modelTags) { modelTag in
                        VStack {
                            HStack {
                                Text(modelTag.model)
                                Spacer()
                            }
                            .frame(height: 26)
                            Divider()
                        }
                    }
                }
                .padding()
            }
            .onAppear {
                store.send(.appear)
            }
        }
    }
}

#Preview {
    if #available(macOS 26.0, *) {
        OllamaSettingView(store: .init(initialState: .init(), reducer: OllamaSettingReducer.init))
    }
}
