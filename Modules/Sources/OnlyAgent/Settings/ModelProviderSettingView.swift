//
//  ModelProviderSettingView.swift
//  Modules
//
//  Created by Bo Liu on 18.11.25.
//

import SwiftUI

@available(macOS 26.0, *)
public struct ModelProviderSettingView: View {
    @State private var selection = 0
    
    public init() {}
    
    public var body: some View {
        TabView {
            OllamaSettingView(store: .init(initialState: .init(), reducer: OllamaSettingReducer.init))
                .tabItem {
                    Text("Ollama")
                }
                .tag(0)
            
            OpenAISettingView(store: .init(initialState: .init(), reducer: OpenAISettingReducer.init))
                .tabItem {
                    Text("Open AI")
                }
                .tag(1)
        }
    }
}

#Preview {
    if #available(macOS 26.0, *) {
        ModelProviderSettingView()
    }
}
