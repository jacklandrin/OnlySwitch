import OnlyAgent
import Testing

struct EvolutionScriptReplyParserTests {
    @Test func parsesSwitchReplyInsideFencesAndProse() throws {
        let reply = """
        Sure!
        ```json
        {"name":"Dark Mode","turn_on":{"kind":"applescript","code":"tell application \\"System Events\\" to tell appearance preferences to set dark mode to true"},
         "turn_off":{"kind":"applescript","code":"tell application \\"System Events\\" to tell appearance preferences to set dark mode to false"},
         "status":{"kind":"applescript","code":"tell application \\"System Events\\" to tell appearance preferences to get dark mode"},
         "status_on_output":" true ","notes":"Needs Automation permission."}
        ```
        """
        let result = try EvolutionScriptReplyParser.parse(reply, target: .switchControl)
        #expect(result.name == "Dark Mode")
        #expect(result.turnOn?.kind == .applescript)
        #expect(result.turnOn?.code.hasPrefix("tell application \"System Events\"") == true)
        #expect(result.statusOnOutput == "true")
        #expect(result.notes == "Needs Automation permission.")
        #expect(result.button == nil)
    }

    @Test func parsesButtonReply() throws {
        let result = try EvolutionScriptReplyParser.parse(#"{"button":{"kind":"shell","code":"open -a Safari"}}"#, target: .button)
        #expect(result.button == GeneratedScript(kind: .shell, code: "open -a Safari"))
        #expect(result.name == nil)
    }

    @Test func unknownKindIsInferredFromCode() throws {
        let shell = try EvolutionScriptReplyParser.parse(#"{"button":{"kind":"bash","code":"ls"}}"#, target: .button)
        #expect(shell.button?.kind == .shell)
        let apple = try EvolutionScriptReplyParser.parse(#"{"button":{"code":"tell application \"Finder\" to activate"}}"#, target: .button)
        #expect(apple.button?.kind == .applescript)
    }

    @Test func switchMissingStatusIsIncomplete() {
        #expect(throws: EvolutionScriptGenerationError.incomplete) {
            try EvolutionScriptReplyParser.parse(#"{"turn_on":{"kind":"shell","code":"a"},"turn_off":{"kind":"shell","code":"b"}}"#, target: .switchControl)
        }
    }

    @Test func switchMissingOnOutputIsIncomplete() {
        #expect(throws: EvolutionScriptGenerationError.incomplete) {
            try EvolutionScriptReplyParser.parse(#"{"turn_on":{"code":"a"},"turn_off":{"code":"b"},"status":{"code":"c"},"status_on_output":"  "}"#, target: .switchControl)
        }
    }

    @Test func buttonReplyForSwitchTargetIsIncomplete() {
        #expect(throws: EvolutionScriptGenerationError.incomplete) {
            try EvolutionScriptReplyParser.parse(#"{"button":{"code":"a"}}"#, target: .switchControl)
        }
    }

    @Test func modelDeclining() {
        #expect(throws: EvolutionScriptGenerationError.declined("Not possible")) {
            try EvolutionScriptReplyParser.parse(#"{"error":"Not possible"}"#, target: .button)
        }
    }

    @Test func proseOnlyIsUnparseable() {
        #expect(throws: EvolutionScriptGenerationError.unparseable) {
            try EvolutionScriptReplyParser.parse("I can't help with that.", target: .button)
        }
    }

    @Test func emptyIsEmptyReply() {
        #expect(throws: EvolutionScriptGenerationError.emptyReply) {
            try EvolutionScriptReplyParser.parse("  \n ", target: .button)
        }
    }

    @Test func promptDescribesTargetContract() {
        let switchPrompt = EvolutionScriptPromptBuilder.systemInstructions(target: .switchControl, systemInfo: .init(osVersion: "26.1"))
        #expect(switchPrompt.contains("status_on_output"))
        #expect(switchPrompt.contains("26.1"))
        #expect(!switchPrompt.contains("\"button\""))
        let buttonPrompt = EvolutionScriptPromptBuilder.systemInstructions(target: .button, systemInfo: .init())
        #expect(buttonPrompt.contains("\"button\""))
        #expect(!buttonPrompt.contains("status_on_output"))
        #expect(EvolutionScriptPromptBuilder.prompt(description: "dim screen").contains("dim screen"))
    }
}
