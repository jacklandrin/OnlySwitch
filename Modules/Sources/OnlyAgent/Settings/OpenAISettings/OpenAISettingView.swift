//
//  OpenAISettingView.swift
//  Modules
//
//  Created by Bo Liu on 20.11.25.
//

import ComposableArchitecture
import SwiftUI
import Design

@available(macOS 26.0, *)
public struct OpenAISettingView: View {
    @Perception.Bindable var store: StoreOf<OpenAISettingReducer>
    
    public init(store: StoreOf<OpenAISettingReducer>) {
        self.store = store
    }
    
    public var body: some View {
        WithPerceptionTracking {
            ScrollView {
                VStack(alignment: .leading) {
                    HStack {
                        Text("API Key:")
                        Spacer()
                    }
                    
                    HStack {
                        SecureInputView("sk-", text: $store.apiKey)
                            
                        if let verified = store.verified {
                            if verified {
                                Text("✅")
                            } else {
                                Text("❌")
                            }
                        }
                        
                        Button {
                            store.send(.check)
                        } label: {
                            Text("Check")
                        }
                    }
                    .padding(.bottom, 10)
                    
                    HStack {
                        Text("API Host:")
                        Spacer()
                    }
                    TextField("", text: $store.host)
                    HStack {
                        Text("https://\(store.host)/v1/responses")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.bottom, 10)
                    HStack {
                        Text("Models:")
                        Spacer()
                    }
                    ForEach(store.models, id: \.self) { model in
                        VStack {
                            HStack {
                                Text(model)
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
        OpenAISettingView(store: .init(initialState: .init(), reducer: OpenAISettingReducer.init))
    }
}
