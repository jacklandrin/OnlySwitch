//
//  OpenAIDataModels.swift
//  Modules
//
//  Created by Bo Liu on 20.11.25.
//

import OpenAI

public struct OpenAIDataModel: AIModel {
    public var model: String
    public var id: String
    
    public init(modelResult: ModelResult) {
        self.model = modelResult.id
        self.id = modelResult.id
    }
    
    public init(model: Model) {
        self.model = model
        self.id = model
    }
}
