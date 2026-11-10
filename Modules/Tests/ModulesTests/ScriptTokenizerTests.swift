import Foundation
import ScriptEditor
import Testing

struct ScriptTokenizerTests {
    private struct Hit: Equatable {
        let kind: ScriptTokenKind
        let text: String
        init(_ kind: ScriptTokenKind, _ text: String) { self.kind = kind; self.text = text }
    }

    private func hits(_ text: String, _ language: ScriptLanguage) -> [Hit] {
        let string = text as NSString
        return ScriptTokenizer.tokens(in: text, language: language).map { Hit($0.kind, string.substring(with: $0.range)) }
    }

    @Test func shellCommentStringVariableKeyword() {
        let result = hits("if [ \"$HOME\" ]; then echo 'hi' # note\nfi", .shell)
        #expect(result.contains(Hit(.keyword, "if")))
        #expect(result.contains(Hit(.keyword, "then")))
        #expect(result.contains(Hit(.keyword, "fi")))
        #expect(result.contains(Hit(.string, "\"$HOME\"")))
        #expect(result.contains(Hit(.string, "'hi'")))
        #expect(result.contains(Hit(.comment, "# note")))
    }

    @Test func shellVariablesOutsideStrings() {
        #expect(hits("echo ${PATH} $1 $#", .shell).filter { $0.kind == .variable }.map(\.text) == ["${PATH}", "$1"])
    }

    @Test func shellHashInsideWordOrStringIsNotComment() {
        #expect(!hits("echo \"a # b\" a#b", .shell).contains { $0.kind == .comment })
    }

    @Test func appleScriptKeywordsCaseInsensitiveAndComments() {
        let result = hits("Tell application \"Finder\" -- c\n(* block\n*) set x to 3\n# hash", .applescript)
        #expect(result.contains(Hit(.keyword, "Tell")))
        #expect(result.contains(Hit(.string, "\"Finder\"")))
        #expect(result.contains(Hit(.comment, "-- c")))
        #expect(result.contains(Hit(.comment, "(* block\n*)")))
        #expect(result.contains(Hit(.number, "3")))
        #expect(result.contains(Hit(.comment, "# hash")))
    }

    @Test func appleScriptSingleQuoteIsNotString() {
        #expect(!hits("say it's", .applescript).contains { $0.kind == .string })
    }

    @Test func escapedQuoteStaysInString() {
        #expect(hits("display dialog \"say \\\"hi\\\"\"", .applescript).contains(Hit(.string, "\"say \\\"hi\\\"\"")))
    }

    @Test func unterminatedConstructsRunToEnd() {
        #expect(hits("echo \"open", .shell).last == Hit(.string, "\"open"))
        #expect(hits("(* open", .applescript).last == Hit(.comment, "(* open"))
        #expect(hits("echo \"trailing\\", .shell).last == Hit(.string, "\"trailing\\"))
    }

    @Test func rangesAreUTF16() {
        #expect(hits("echo 🎉 # done", .shell).last == Hit(.comment, "# done"))
    }

    @Test func emptyTextHasNoTokens() {
        #expect(ScriptTokenizer.tokens(in: "", language: .shell).isEmpty)
        #expect(ScriptTokenizer.tokens(in: "$", language: .shell).isEmpty)
    }

    @Test func crlfLineEndingsKeepCommentsOnOneLine() {
        #expect(hits("# a\r\necho", .shell).first == Hit(.comment, "# a\r"))
        #expect(hits("# a\r\necho", .shell).contains(Hit(.keyword, "echo")))
    }
}
