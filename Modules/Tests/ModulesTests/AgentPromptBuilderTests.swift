import Foundation
import Testing
@testable import OnlyAgent

struct AgentPromptBuilderTests {
    @Test
    func systemInstructionsDescribeContractAndComputer() {
        let instructions = AgentPromptBuilder.systemInstructions(systemInfo: .fixture)
        #expect(instructions.contains(#""type":"questions""#))
        #expect(instructions.contains(#""type":"plan""#))
        #expect(instructions.contains(#""type":"message""#))
        #expect(instructions.contains("applescript"))
        #expect(instructions.contains("shell"))
        #expect(instructions.contains("macOS 26.1.0 (build 26B82)"))
        #expect(instructions.contains("Apple Silicon (arm64)"))
        #expect(instructions.contains("Mac16,1"))
        #expect(instructions.contains("16 GB"))
        #expect(instructions.contains("zh-Hans"))
        #expect(instructions.contains("Region: DE"))
        #expect(instructions.contains("Displays: 2"))
        #expect(instructions.contains("Appearance: Dark"))
        #expect(instructions.contains("sudo -A"))
        #expect(instructions.contains("SUDO_ASKPASS"))
    }

    @Test
    func unknownSystemInfoFieldsAreOmitted() {
        let description = AgentSystemInfo(osVersion: "26.0.0").promptDescription
        #expect(description == "- macOS 26.0.0")
    }

    @Test
    func intelArchitectureIsDescribed() {
        let description = AgentSystemInfo(osVersion: "15.6.0", architecture: "x86_64").promptDescription
        #expect(description.contains("Intel (x86_64)"))
    }

    @Test
    func promptSerializesTranscript() {
        var failed = AgentScriptStep(id: UUID(), title: "Set volume", kind: .shell, code: "osascript -e 'set volume 3'")
        failed.status = .failed
        failed.error = "Permission denied"
        var question = AgentQuestion(id: UUID(), prompt: "Which display?", options: ["Built-in", "External"])
        question.answer = "Built-in"
        let messages: [AgentMessage] = [
            AgentMessage(id: UUID(), role: .user, content: .text("Dim my screen")),
            AgentMessage(id: UUID(), role: .assistant, content: .questions([question], answered: true)),
            AgentMessage(id: UUID(), role: .assistant, content: .plan(AgentPlan(id: UUID(), title: "Dim", summary: "", steps: [failed]))),
            AgentMessage(id: UUID(), role: .assistant, content: .error("Network down")),
        ]

        let prompt = AgentPromptBuilder.prompt(for: messages)

        #expect(prompt.contains("User: Dim my screen"))
        #expect(prompt.contains("Which display?: Built-in"))
        #expect(prompt.contains("Dim"))
        #expect(prompt.contains("[shell] Set volume"))
        #expect(prompt.contains("Step 1 failed: Permission denied"))
        #expect(prompt.contains("Error: Network down"))
        #expect(!prompt.contains("Only Agent, a macOS automation agent"))
    }

    @Test
    func unansweredQuestionsDoNotIncludeAnswers() {
        let question = AgentQuestion(id: UUID(), prompt: "Which?", options: [])
        let prompt = AgentPromptBuilder.prompt(
            for: [AgentMessage(id: UUID(), role: .assistant, content: .questions([question], answered: false))]
        )
        #expect(prompt.contains("Which?"))
        #expect(!prompt.contains("User answered"))
    }

    @Test
    func transcriptIsCappedToRecentMessages() {
        let messages = (0..<30).map {
            AgentMessage(id: UUID(), role: .user, content: .text("message-\($0)-end"))
        }
        let prompt = AgentPromptBuilder.prompt(for: messages)
        #expect(!prompt.contains("message-9-end"))
        #expect(prompt.contains("message-10-end"))
        #expect(prompt.contains("message-29-end"))
    }
}
