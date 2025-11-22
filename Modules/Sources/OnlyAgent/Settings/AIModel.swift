//
//  AIModel.swift
//  Modules
//
//  Created by Bo Liu on 20.11.25.
//

public protocol AIModel {
    var model: String { get }
    var id: String { get }
}

struct ToolArguments {
    let prompt: String
    let model: String
}
