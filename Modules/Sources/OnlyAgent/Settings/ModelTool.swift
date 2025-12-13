//
//  ModelTool.swift
//  Modules
//
//  Created by Bo Liu on 06.12.25.
//

public enum ModelProvider: String {
    case ollama
    case openai
    case gemini
}

protocol ModelTool {
    func call(arguments: ToolArguments) async throws -> String
}

public protocol AIModel {
    var model: String { get }
    var id: String { get }
}

struct ToolArguments {
    let prompt: String
    let model: String
}

public struct ProviderModel {
    var model: String
    var id: String 
}

extension ProviderModel {
    init(model: String) {
        self.model = model
        self.id = model
    }
}
