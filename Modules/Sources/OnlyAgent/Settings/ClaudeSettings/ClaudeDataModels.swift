//
//  ClaudeDataModels.swift
//  Modules
//
//  Created by Louis Saks on 23.06.26.
//

public struct ClaudeDataModel: AIModel {
    public var model: String
    public var id: String

    public init(name: String) {
        self.model = name
        self.id = name
    }
}
