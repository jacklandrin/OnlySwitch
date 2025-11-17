//
//  EvolutionGalleryModel.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/2.
//

import Foundation

struct EvolutionGalleryModel: Codable {
    enum CodingKeys: CodingKey {
        case id
        case name
        case icon_name
        case type
        case description
        case author
        case on_command
        case off_command
        case check_command
        case single_command
    }
    var id: String
    var name: String
    var icon_name: String
    var type: String
    var description: String
    var author: String
    var on_command: EvolutionGalleryCommand?
    var off_command: EvolutionGalleryCommand?
    var check_command: EvolutionGalleryCommand?
    var single_command: EvolutionGalleryCommand?
}

struct EvolutionGalleryCommand: Codable {
    enum CodingKeys: CodingKey {
        case type
        case command
        case true_condition
    }

    var type: String
    var command: String
    var true_condition: String?
}
