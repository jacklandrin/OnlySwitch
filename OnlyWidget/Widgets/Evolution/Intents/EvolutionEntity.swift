//
//  EvolutionEntity.swift
//  OnlyWidgetExtension
//
//  Created by Jacklandrin on 2024/6/9.
//

import AppIntents

struct EvolutionEntity: AppEntity {
    var id: UUID
    var evolution: EvolutionWidgetModel
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Evolution"
    static var defaultQuery = EvolutionQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(evolution.title)")
    }

    static func allEvolutions() async -> [EvolutionEntity]  {
        do {
           return try await EvolutionCommandEntity.fetchResult()
                .compactMap { (entity: EvolutionCommandEntity) -> EvolutionEntity? in
                    guard let id = entity.id,
                          let name = entity.name else {
                        return nil
                    }
                    return .init(id: id, evolution: .init(id: id, title:name, imageName: entity.iconName))
                }
        } catch {
            return []
        }
    }
}

struct EvolutionQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [EvolutionEntity] {
        await EvolutionEntity.allEvolutions()
            .filter{
                $0.evolution.title.range(of: string, options: .caseInsensitive) != nil
            }
    }

    func entities(for identifiers: [EvolutionEntity.ID]) async throws -> [EvolutionEntity] {
        identifiers.compactMap {
            try? EvolutionCommandEntity.fetchRequest(by: $0)
        }
        .compactMap { (entity: EvolutionCommandEntity) -> EvolutionEntity? in
            guard let id = entity.id,
                  let name = entity.name else {
                return nil
            }
            return .init(id: id, evolution: .init(id: id, title:name, imageName: entity.iconName))
        }
    }

    func suggestedEntities() async throws -> [EvolutionEntity] {
        await EvolutionEntity.allEvolutions()
    }

    func defaultResult() async -> EvolutionEntity? {
        await EvolutionEntity.allEvolutions().first
    }

    func defaultResult() -> EvolutionEntity? {
        let id = UUID()
        return EvolutionEntity(id: id, evolution: .init(id: id, title: "Default Evolution", imageName: nil))
    }
}
