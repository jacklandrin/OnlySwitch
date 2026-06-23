//
//  ClaudeSettingView.swift
//  Modules
//
//  Created by Louis Saks on 23.06.26.
//

import ComposableArchitecture
import SwiftUI
import Design

@available(macOS 26.0, *)
public struct ClaudeSettingView: View {
    @SwiftUI.Bindable var store: StoreOf<ClaudeSettingReducer>

    public init(store: StoreOf<ClaudeSettingReducer>) {
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
                        SecureInputView("sk-ant-...", text: $store.apiKey)

                        if store.isVerifying {
                            AppKitProgressView()
                                .scaleEffect(0.6)
                        } else {
                            if let verified = store.verified {
                                if verified {
                                    Text("✅")
                                } else {
                                    Text("❌")
                                }
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
    if #available(macOS 26.0, *) {
        ClaudeSettingView(store: .init(initialState: .init(), reducer: ClaudeSettingReducer.init))
    }
}
