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
}
