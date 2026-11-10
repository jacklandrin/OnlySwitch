import Foundation
import Testing
@testable import OnlyAgent

struct AgentReplyParserTests {
    @Test
    func parsesFencedPlanWithMixedKinds() throws {
        let text = """
        Sure!
        ```json
        {"type":"plan","title":"T","summary":"S","steps":[
          {"title":"A","kind":"applescript","code":"tell application \\"Finder\\" to activate"},
          {"title":"B","kind":"shell","code":"defaults write -g AppleInterfaceStyle Dark"}]}
        ```
        """
        guard case let .plan(plan) = AgentReplyParser.parse(text) else {
            Issue.record("Expected a plan")
            return
        }
        #expect(plan.title == "T")
        #expect(plan.summary == "S")
        #expect(plan.steps.map(\.kind) == [.applescript, .shell])
        #expect(plan.steps.map(\.title) == ["A", "B"])
        #expect(plan.steps[0].code == "tell application \"Finder\" to activate")
        #expect(plan.steps.allSatisfy { $0.status == .pending })
    }

    @Test
    func parsesQuestionsWithAndWithoutOptions() {
        let reply = AgentReplyParser.parse(
            #"{"type":"questions","questions":[{"question":"Which?","options":["A","B"]},{"question":"Name?"}]}"#
        )
        guard case let .questions(questions) = reply else {
            Issue.record("Expected questions")
            return
        }
        #expect(questions.map(\.prompt) == ["Which?", "Name?"])
        #expect(questions[0].options == ["A", "B"])
        #expect(questions[1].options.isEmpty)
        #expect(questions.allSatisfy { $0.answer.isEmpty })
    }

    @Test
    func unknownKindDefaultsToAppleScriptAndEmptyCodeIsDropped() {
        let reply = AgentReplyParser.parse(
            #"{"type":"plan","title":"T","summary":"","steps":[{"title":"A","kind":"python","code":"x"},{"title":"B","kind":"shell","code":"  "}]}"#
        )
        guard case let .plan(plan) = reply else {
            Issue.record("Expected a plan")
            return
        }
        #expect(plan.steps.count == 1)
        #expect(plan.steps[0].kind == .applescript)
    }

    @Test
    func emptyStepsBecomesMessage() {
        let reply = AgentReplyParser.parse(#"{"type":"plan","title":"T","summary":"nothing to do","steps":[]}"#)
        #expect(reply == .message("nothing to do"))
    }

    @Test
    func messageType() {
        #expect(AgentReplyParser.parse(#"{"type":"message","text":"No way"}"#) == .message("No way"))
    }

    @Test
    func rawAppleScriptFallsBackToSingleStepPlan() {
        guard case let .plan(plan) = AgentReplyParser.parse("```applescript\ntell application \"System Events\" to key code 144\n```") else {
            Issue.record("Expected a plan")
            return
        }
        #expect(plan.steps.count == 1)
        #expect(plan.steps[0].kind == .applescript)
        #expect(plan.steps[0].code == "tell application \"System Events\" to key code 144")
    }

    @Test
    func plainProseBecomesMessage() {
        #expect(AgentReplyParser.parse("  I cannot do that.\n") == .message("I cannot do that."))
    }

    @Test
    func usesInjectedIdentifiers() {
        var counter = 0
        let makeID: () -> UUID = {
            counter += 1
            return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", counter))!
        }
        guard case let .plan(plan) = AgentReplyParser.parse(
            #"{"type":"plan","title":"T","summary":"","steps":[{"title":"A","kind":"shell","code":"true"}]}"#,
            makeID: makeID
        ) else {
            Issue.record("Expected a plan")
            return
        }
        #expect(plan.steps[0].id == UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        #expect(plan.id == UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
    }
}
