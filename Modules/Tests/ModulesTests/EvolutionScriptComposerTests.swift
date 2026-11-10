import Foundation
import Testing
@testable import OnlyAgent

struct EvolutionScriptComposerTests {
    @Test
    func composeWrapsEachStepAndEscapes() {
        let steps = [
            AgentScriptStep(id: UUID(), title: "a", kind: .applescript, code: "display notification \"hi\""),
            AgentScriptStep(id: UUID(), title: "b", kind: .shell, code: #"echo "x\y""#),
        ]
        #expect(EvolutionScriptComposer.compose(steps) == #"""
        run script "display notification \"hi\""
        do shell script "echo \"x\\y\""
        """#)
    }

    @Test
    func multilineAppleScriptStaysInsideOneLiteral() {
        let step = AgentScriptStep(id: UUID(), title: "a", kind: .applescript, code: "tell application \"Finder\"\n  activate\nend tell")
        #expect(EvolutionScriptComposer.compose([step]) == "run script \"tell application \\\"Finder\\\"\n  activate\nend tell\"")
    }

    @Test
    func emptyPlanComposesToEmptyString() {
        #expect(EvolutionScriptComposer.compose([]).isEmpty)
    }

    @Test
    func sudoShellStepGetsAskpassWhenSaved() {
        let steps = [
            AgentScriptStep(id: UUID(), title: "a", kind: .shell, code: "sudo -A true"),
            AgentScriptStep(id: UUID(), title: "b", kind: .shell, code: "echo hi"),
        ]
        #expect(EvolutionScriptComposer.compose(steps, askpassPath: "/tmp/ask pass.sh") == #"""
        do shell script "export SUDO_ASKPASS='/tmp/ask pass.sh'
        sudo -A true"
        do shell script "echo hi"
        """#)
    }

    @Test
    func needsAskpassDetectsSudoAndHomebrew() {
        #expect(EvolutionScriptComposer.needsAskpass([AgentScriptStep(id: UUID(), title: "", kind: .shell, code: "/opt/homebrew/bin/brew upgrade")]))
        #expect(EvolutionScriptComposer.needsAskpass([AgentScriptStep(id: UUID(), title: "", kind: .shell, code: "sudo -A ls")]))
        #expect(!EvolutionScriptComposer.needsAskpass([AgentScriptStep(id: UUID(), title: "", kind: .applescript, code: "sudo")]))
        #expect(!EvolutionScriptComposer.needsAskpass([AgentScriptStep(id: UUID(), title: "", kind: .shell, code: "echo hi")]))
    }
}
