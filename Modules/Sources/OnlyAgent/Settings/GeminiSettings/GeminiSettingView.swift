//
//  GeminiSettingView.swift
//  Modules
//
//  Created by Bo Liu on 06.12.25.
//

import ComposableArchitecture
import SwiftUI
import Design

public struct GeminiSettingView: View {
    @Perception.Bindable var store: StoreOf<GeminiSettingReducer>
    
    public init(store: StoreOf<GeminiSettingReducer>) {
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
                        SecureInputView("", text: $store.apiKey)
                            
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
    GeminiSettingView(store: .init(initialState: .init(), reducer: GeminiSettingReducer.init))
}

