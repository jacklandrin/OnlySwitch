//
//  ModelProviderSettingView.swift
//  Modules
//
//  Created by Bo Liu on 18.11.25.
//

import SwiftUI

@available(macOS 26.0, *)
public struct ModelProviderSettingView: View {
    @State private var selection: ModelProvider = .ollama
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Custom Tab Bar
            HStack(spacing: 0) {
                CustomTabItem(
                    icon: "ollama",
                    title: "Ollama",
                    isSelected: selection == .ollama
                ) {
                    selection = .ollama
                }
                
                CustomTabItem(
                    icon: "openai",
                    title: "Open AI",
                    isSelected: selection == .openai
                ) {
                    selection = .openai
                }
                
                CustomTabItem(
                    icon: "gemini",
                    title: "Gemini",
                    isSelected: selection == .gemini
                ) {
                    selection = .gemini
                }
            }
            .frame(height: 70)
            .background(Color(NSColor.controlBackgroundColor))
                        
            // Content Area
            Group {
                switch selection {
                    case .ollama:
                        OllamaSettingView(store: .init(initialState: .init(), reducer: OllamaSettingReducer.init))
                    case .openai:
                        OpenAISettingView(store: .init(initialState: .init(), reducer: OpenAISettingReducer.init))
                    case .gemini:
                        GeminiSettingView(store: .init(initialState: .init(), reducer: GeminiSettingReducer.init))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@available(macOS 26.0, *)
private struct CustomTabItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(icon, bundle: .module)
                    .resizable()
                    .scaledToFit()
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? .blue : (isHovered ? .blue.opacity(0.7) : .primary))
                    .frame(width: 30, height: 30)
                
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .blue : (isHovered ? .blue.opacity(0.7) : .primary))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.blue.opacity(0.2) : (isHovered ? Color.blue.opacity(0.1) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .frame(width: 70)
    }
}

#Preview {
    if #available(macOS 26.0, *) {
        ModelProviderSettingView()
            .frame(width: 800, height: 600)
    }
}
