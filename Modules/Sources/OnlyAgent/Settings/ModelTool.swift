//
//  ModelTool.swift
//  Modules
//
//  Created by Bo Liu on 06.12.25.
//

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
