import ComposableArchitecture
import DesktopPetSkinKit
import Foundation
import Testing
@testable import OnlyAgent

struct DesktopPetSkinGenerationTests {
    static let valid = DesktopPetSkinFixture.valid

    @Test func returnsValidDraftOnFirstTry() async throws {
        let calls = LockIsolated<[String]>([])
        let draft = try await DesktopPetSkinGenerationClient.generate(description: "cat") { prompt in
            calls.withValue { $0.append(prompt) }
            return "NAME: Cat\n```html\n\(Self.valid)\n```"
        }
        #expect(draft == DesktopPetSkinDraft(name: "Cat", markup: Self.valid))
        #expect(calls.value.count == 1)
        #expect(calls.value.first?.contains("cat") == true)
    }

    @Test func repairsOnceWithValidationHint() async throws {
        let calls = LockIsolated<[String]>([])
        let draft = try await DesktopPetSkinGenerationClient.generate(description: "cat") { prompt in
            let count = calls.withValue { $0.append(prompt); return $0.count }
            return count == 1 ? "```html\n<div id=\"pet\"></div>\n```" : "NAME: Cat\n```html\n\(Self.valid)\n```"
        }
        #expect(draft.markup == Self.valid)
        #expect(calls.value.count == 2)
        #expect(calls.value.last?.contains("missing states") == true)
    }

    @Test func failsAfterSecondInvalidReply() async {
        let calls = LockIsolated(0)
        await #expect(throws: DesktopPetSkinGenerationError.invalid(.forbidden("disallowed element"))) {
            _ = try await DesktopPetSkinGenerationClient.generate(description: "cat") { _ in
                calls.withValue { $0 += 1 }
                return "```html\n<script></script>\(Self.valid)\n```"
            }
        }
        #expect(calls.value == 2)
    }

    @Test func failsAfterSecondReplyWithoutMarkup() async {
        let calls = LockIsolated(0)
        await #expect(throws: DesktopPetSkinGenerationError.noMarkup) {
            _ = try await DesktopPetSkinGenerationClient.generate(description: "cat") { _ in
                calls.withValue { $0 += 1 }
                return "I would rather not draw today."
            }
        }
        #expect(calls.value == 2)
    }

    @Test func refusalIsNotRetried() async {
        let calls = LockIsolated<[String]>([])
        await #expect(throws: DesktopPetSkinGenerationError.refused("no")) {
            _ = try await DesktopPetSkinGenerationClient.generate(description: "x") { prompt in
                calls.withValue { $0.append(prompt) }
                return "ERROR: no"
            }
        }
        #expect(calls.value.count == 1)
    }

    // MARK: - Edit

    static let base = DesktopPetSkinDraft(name: "Sleepy Cat", markup: valid)

    @Test func editReturnsValidDraftOnFirstTry() async throws {
        let calls = LockIsolated<[String]>([])
        let draft = try await DesktopPetSkinGenerationClient.edit(instruction: "add a hat", base: Self.base) { prompt in
            calls.withValue { $0.append(prompt) }
            return "NAME: Wizard Cat\n```html\n\(Self.valid)\n```"
        }
        #expect(draft == DesktopPetSkinDraft(name: "Wizard Cat", markup: Self.valid))
        #expect(calls.value == [
            DesktopPetSkinPromptBuilder.editPrompt(
                instruction: "add a hat", currentName: Self.base.name, currentMarkup: Self.base.markup
            ),
        ])
    }

    @Test func editKeepsBaseNameWhenReplyHasNone() async throws {
        let draft = try await DesktopPetSkinGenerationClient.edit(instruction: "add a hat", base: Self.base) { _ in
            "```html\n  \(Self.valid)  \n```"
        }
        #expect(draft == DesktopPetSkinDraft(name: "Sleepy Cat", markup: Self.valid))
    }

    @Test func editRepairsOnceWithValidationHint() async throws {
        let calls = LockIsolated<[String]>([])
        let rejected = "<div id=\"pet\"></div>"
        let draft = try await DesktopPetSkinGenerationClient.edit(instruction: "add a hat", base: Self.base) { prompt in
            let count = calls.withValue { $0.append(prompt); return $0.count }
            return count == 1 ? "```html\n\(rejected)\n```" : "NAME: Sleepy Cat\n```html\n\(Self.valid)\n```"
        }
        #expect(draft.markup == Self.valid)
        #expect(calls.value.count == 2)
        let repair = try #require(calls.value.last)
        #expect(repair.contains("missing states"))
        #expect(repair.contains("add a hat"))
        #expect(repair.contains(rejected))
    }

    @Test func editFailsAfterSecondInvalidReply() async {
        let calls = LockIsolated(0)
        await #expect(throws: DesktopPetSkinGenerationError.invalid(.forbidden("disallowed element"))) {
            _ = try await DesktopPetSkinGenerationClient.edit(instruction: "add a hat", base: Self.base) { _ in
                calls.withValue { $0 += 1 }
                return "```html\n<script></script>\(Self.valid)\n```"
            }
        }
        #expect(calls.value == 2)
    }

    @Test func editRefusalIsNotRetried() async {
        let calls = LockIsolated(0)
        await #expect(throws: DesktopPetSkinGenerationError.refused("no")) {
            _ = try await DesktopPetSkinGenerationClient.edit(instruction: "x", base: Self.base) { _ in
                calls.withValue { $0 += 1 }
                return "ERROR: no"
            }
        }
        #expect(calls.value == 1)
    }

    @Test func editClientDefaultsToNoModelSelected() async {
        await #expect(throws: DesktopPetSkinGenerationError.noModelSelected) {
            _ = try await DesktopPetSkinGenerationClient().edit("x", Self.base)
        }
    }
}
