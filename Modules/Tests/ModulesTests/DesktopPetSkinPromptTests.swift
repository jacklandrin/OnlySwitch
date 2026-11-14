import DesktopPetSkinKit
import Testing

struct DesktopPetSkinPromptTests {
    @Test func systemInstructionsListEveryStateAndAttribute() {
        let text = DesktopPetSkinPromptBuilder.systemInstructions
        for state in DesktopPetSkinContract.requiredStates {
            #expect(text.contains("\"\(state)\""))
        }
        for attribute in ["data-state", "data-control", "data-pomodoro", "data-hungry", "data-reduce-motion", "data-paused"] {
            #expect(text.contains(attribute))
        }
        #expect(text.contains("no JavaScript"))
    }

    @Test func promptCarriesTheDescription() {
        #expect(DesktopPetSkinPromptBuilder.prompt(description: "a sleepy cat").contains("a sleepy cat"))
    }

    @Test func repairPromptCarriesTheHint() {
        let prompt = DesktopPetSkinPromptBuilder.repairPrompt(
            description: "a cat", previousMarkup: "<div id=\"pet\"></div>", error: .missingStates(["eating"])
        )
        #expect(prompt.contains("eating"))
        #expect(prompt.contains("a cat"))
        #expect(prompt.contains("<div id=\"pet\"></div>"))
    }

    @Test func parsesNameAndFencedMarkup() throws {
        let reply = "Sure!\nNAME: Sleepy Cat\n```html\n<style>a{}</style><svg id=\"pet\"></svg>\n```\nEnjoy"
        #expect(try DesktopPetSkinReplyParser.parse(reply) == DesktopPetSkinDraft(
            name: "Sleepy Cat", markup: "<style>a{}</style><svg id=\"pet\"></svg>"
        ))
    }

    @Test func parsesUnfencedMarkupAndDefaultsName() throws {
        let draft = try DesktopPetSkinReplyParser.parse("<style>a{}</style><div id=\"pet\"></div>")
        #expect(draft.markup.hasPrefix("<style>"))
        #expect(draft.name.isEmpty)
    }

    @Test func surfacesRefusal() {
        #expect(throws: DesktopPetSkinReplyError.refused("not appropriate")) {
            try DesktopPetSkinReplyParser.parse("ERROR: not appropriate")
        }
    }

    @Test func rejectsReplyWithoutMarkup() {
        #expect(throws: DesktopPetSkinReplyError.noMarkup) {
            try DesktopPetSkinReplyParser.parse("I cannot do that.")
        }
    }
}
