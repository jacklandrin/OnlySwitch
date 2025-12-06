//
//  GeminiDataModels.swift
//  Modules
//
//  Created by Bo Liu on 06.12.25.
//

public struct GeminiDataModel: AIModel {
    public var model: String
    public var id: String
    
    public init(name: String) {
        self.model = name
        self.id = name
    }
}
