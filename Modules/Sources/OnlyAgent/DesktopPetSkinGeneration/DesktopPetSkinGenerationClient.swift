import Dependencies
import DesktopPetSkinKit
import Foundation
import OSLog
import Sharing

public enum DesktopPetSkinGenerationError: Error, Equatable, Sendable {
    case noModelSelected
    case refused(String)
    case invalid(DesktopPetSkinValidationError)
    case noMarkup
}

/// Writes a desktop pet skin from a description with the model chosen in Only Agent. The result
/// is validated here and again before it is saved and rendered.
public struct DesktopPetSkinGenerationClient: Sendable {
    public var isModelSelected: @Sendable () -> Bool
    public var generate: @Sendable (_ description: String) async throws -> DesktopPetSkinDraft

    public init(
        isModelSelected: @escaping @Sendable () -> Bool = { false },
        generate: @escaping @Sendable (String) async throws -> DesktopPetSkinDraft = { _ in
            throw DesktopPetSkinGenerationError.noModelSelected
        }
    ) {
        self.isModelSelected = isModelSelected
        self.generate = generate
    }

    /// One generation plus at most one repair round. `send` returns the model's full reply to a prompt.
    static func generate(
        description: String,
        send: @Sendable (String) async throws -> String
    ) async throws -> DesktopPetSkinDraft {
        var prompt = DesktopPetSkinPromptBuilder.prompt(description: description)
        for attempt in 0..<2 {
            let draft: DesktopPetSkinDraft
            do {
                draft = try DesktopPetSkinReplyParser.parse(try await send(prompt))
            } catch let error as DesktopPetSkinReplyError {
                switch error {
                case let .refused(reason): throw DesktopPetSkinGenerationError.refused(reason)
                case .noMarkup:
                    if attempt == 1 { throw DesktopPetSkinGenerationError.noMarkup }
                    prompt = DesktopPetSkinPromptBuilder.repairPrompt(description: description, previousMarkup: "", error: .empty)
                    continue
                }
            }
            do {
                let markup = try DesktopPetSkinValidator.validate(draft.markup)
                return DesktopPetSkinDraft(name: draft.name, markup: markup)
            } catch {
                Logger.onlyAgentDebug.warning("Desktop pet skin rejected: \(error.category, privacy: .public)")
                if attempt == 1 { throw DesktopPetSkinGenerationError.invalid(error) }
                prompt = DesktopPetSkinPromptBuilder.repairPrompt(
                    description: description, previousMarkup: draft.markup, error: error
                )
            }
        }
        throw DesktopPetSkinGenerationError.noMarkup
    }
}

extension DesktopPetSkinGenerationClient: DependencyKey {
    public static var liveValue: Self {
        @Dependency(\.modelProviderService) var modelProviderService
        let service = modelProviderService
        return Self(
            isModelSelected: {
                @Shared(.currentAIModel) var current
                return current?.modelProvider != nil
            },
            generate: { description in
                @Shared(.currentAIModel) var current
                guard let current, let provider = current.modelProvider else {
                    throw DesktopPetSkinGenerationError.noModelSelected
                }
                return try await generate(description: description) { prompt in
                    let request = ModelGenerationRequest(
                        provider: provider,
                        model: current.model,
                        purpose: .agent,
                        systemInstructions: DesktopPetSkinPromptBuilder.systemInstructions,
                        prompt: prompt,
                        maximumOutputTokens: 16_384
                    )
                    var accumulated = ""
                    var finalText: String?
                    for try await event in try await service.instructedChatStream(request) {
                        switch event {
                        case let .contentDelta(delta): accumulated += delta
                        case .thinkingDelta: break
                        case let .completed(text): finalText = text.isEmpty ? accumulated : text
                        }
                    }
                    return finalText ?? accumulated
                }
            }
        )
    }

    public static let testValue = Self()
}

extension DependencyValues {
    public var desktopPetSkinGeneration: DesktopPetSkinGenerationClient {
        get { self[DesktopPetSkinGenerationClient.self] }
        set { self[DesktopPetSkinGenerationClient.self] = newValue }
    }
}
