# Writing better tests

This contains suggestions to help you write better tests. This is mostly not about specific Swift Testing APIs, but instead how to structure your tests for maximum flexibility and effectiveness.


## Encourage unit test hygiene

Good unit tests should fit the acronym FIRST:

- Fast: you should be able to run dozens of them every second, if not hundreds or even thousands.
- Isolated: they should not depend on another test having run, or any sort of external state.
- Repeatable: they should always give the same result when they are run, regardless of how many times or when they are run.
- Self-verifying: the test must unambiguously say whether it passed or failed, with no room for interpretation.
- Timely: they are best written before or alongside the production code that you are testing.

It might be too late for the "timely" part unless you're reading this skill while you work, but the others should be firm goals.


## Test generation heuristics

For a given function, aim to generate the following tests:

- Happy path tests
- Boundary tests
- Invalid input tests

And, if appropriate, concurrency tests.


## Testing SwiftUI views

Never test views directly – they use `@State` and are likely to behave unpredictably.

Instead, test view models or similar. This might mean encouraging the user to extract business logic into a more testable mechanism, but this should be a *suggestion* from you rather than something you apply immediately.

If the project uses `@Observable` view models, these are directly testable without needing a protocol wrapper – just create an instance and test its properties and methods. For more help with SwiftUI, suggest the [SwiftUI Pro agent skill](https://github.com/twostraws/swiftui-agent-skill).


## Structuring tests

Prefer to organize test types in a pattern that matches the production code. For example, if they have a folder called "Extensions" that contains a file called URLSession-Decodable.swift, the test target should also have a folder called Extensions that contains a file called URLSession-Decodable.swift, and it should test the contents of the original production file.

**If you are writing new tests, follow this rule. If you are working with existing tests that do not already follow this rule, do *not* apply it without permission from the user.**

- Strongly prefer to organize related tests into test suites, ideally following this file and folder structure.
- If there are test fixtures, put them in a dedicated file. If there are only a handful, a simple Fixtures folder is fine. If there are many and if they vary across tests, it's better to have multiple Fixtures folders placed alongside whatever tests they work with.
- Use tags to mark up different kinds of work. At the very least this should be a `.networking` tag for network-related tests, even if they are mocked. You might also consider `.slow` for any tests that are unexpectedly slow, `.edgeCase` for tests that must be treated with extra care, `.smoke` for smoke tests, and more.
- Add user-facing messages to `#expect` and `#require` when they provide value. This is not *always* the case, but it usually is.
- Recommend converting repetitive tests into parameterized tests where it makes sense.
- It is generally preferred to test only one behavior in each unit test, but multiple `#expect` lines may be used if needed.


## Expose hidden dependencies

Strongly prefer to avoid hidden dependencies in production code you are testing. In Swift apps this is commonly things like `UserDefaults` or `URLSession`.

For example, production code like this is bad because it has a hidden dependency on `URLSession`:

```swift
struct News {
    var url: URL
    var stories = ""

    mutating func fetch() async throws {
        let (data, _) = try await URLSession.shared.data(from: url)
        stories = String(decoding: data, as: UTF8.self)
    }
}
```

To remove the hidden dependency, a first step would be to inject the `URLSession` like this:

```swift
func fetch(using session: URLSession = .shared) async throws {
    let (data, _) = try await session.data(from: url)
    stories = String(decoding: data, as: UTF8.self)
}
```

Importantly, this also does not change the way the `fetch()` method is called because it has a default value of whatever was used before.

Even better would be to wrap `URLSession` in a protocol, requiring whatever methods are used in the production code, like this:

```swift
protocol URLSessionProtocol {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol { }
```

And now the production code can be written like this:

```swift
func fetch(using session: any URLSessionProtocol = URLSession.shared) async throws {
    let (data, _) = try await session.data(from: url)
    stories = String(decoding: data, as: UTF8.self)
}
```

This then allows you to create a mock version of `URLSession` for tests, removing any live networking from tests. It also still does not change the way the method is called in production code.

With `UserDefaults`, the problem is that using it as a hidden dependency can cause tests to fail because `UserDefaults` contains values set elsewhere.

So, switch over to dependency injection with a sensible default value of whatever the project was using previously, then in the test pass in a custom `UserDefaults` instance like this:

```swift
let suite = "suite-\(UUID().uuidString)"
let userDefaults = UserDefaults(suiteName: suite)
defer { userDefaults?.removePersistentDomain(forName: suite) }
```

That creates a local `UserDefaults` instance in the test and ensures it's deleted fully before the test completes.

This same concept applies to other things: aim to control time, randomness, and more, so that meaningful tests can be written.


## Expect vs require

Both `#expect` and `#require` evaluate a condition and fail the test if it's false. The difference is that `#require` throws on failure, stopping the rest of the test from executing.

**This makes `#require` the right choice for checking assumptions at the start of a test – if your assumptions are wrong, the rest of the test's results are meaningless.**

Using `#require` requires adding `throws` to your test method. For example, if your test depends on some setup being correct before the real assertion:

```swift
@Test func outstandingTasksStringIsPlural() throws {
    let sut = try createTestUser(projects: 3, itemsPerProject: 10)
    try #require(sut.projects.isEmpty == false)
    let rowTitle = sut.outstandingTasksString
    #expect(rowTitle == "30 items")
}
```

If the `#require` fails, the test stops immediately rather than producing confusing secondary failures. Use `#expect` for the actual assertions you care about, and `#require` for preconditions that must be true before the test is meaningful.

`#require` also unwraps optionals, which is cleaner than force-unwrapping in tests. Use it like this:

```swift
let value = try #require(someOptional)
```


## Tracking bug fixes

If you are writing tests related to a specific bug, it is a good idea to use the `.bug` trait to store the bug ID or URL, if there is one. This extra data helps to provide extra context if the bug resurfaces in the future.

For example, if bug #182 is a report that text headings are not italicized correctly, you would use `@Test` like this:

```swift
@Test("Headings should always be italic", .bug(id: 182))
```

Or if there is a specific URL:

```swift
@Test("Headings should always be italic", .bug("https://github.com/you/repo/issues/182"))
```


## Use Issue.record() for throw-testing

When testing that a function throws, the simplest approach is a `do`/`try`/`catch` block with `Issue.record()` as the failure primitive. If no error is thrown, execution continues past `try` and hits `Issue.record()`, failing the test.

```swift
@Test func playingMinecraftThrows() {
    let game = Game(name: "Minecraft")

    do {
        try game.play()
        Issue.record("Expected an error to be thrown.")
    } catch GameError.notPurchased {
        // success
    } catch {
        Issue.record("Wrong error thrown: \(error)")
    }
}
```

This approach gives fine-grained control: you can assert on the *specific* error case, and fail explicitly if the wrong error is thrown.

An alternative is using `#expect(throws:)`. Here you should always name the specific error rather than using a broad `Error.self`:

```swift
// Bad – passes for any error
#expect(throws: Error.self) {
    try game.play()
}

// Good – asserts the exact error case
#expect(throws: GameError.notInstalled) {
    try game.play()
}
```

To assert that a function does *not* throw, use `Never.self`:

```swift
#expect(throws: Never.self) {
    try game.play()
}
```


## Making test results easier to read

In test targets, you can add `CustomTestStringConvertible` conformances to custom types to make them easier to read in test results.

For example, without this conformance a test that catches a `parentalControlsDisallowed` error might result in output like this:

```
Test patchMatchThrows() recorded an issue at ThrowingTests.swift:61:6: Caught error: parentalControlsDisallowed
```

If we add a retroactive conformance to `CustomTestStringConvertible` in the test target, the text can be clarified:

```swift
extension GameError: @retroactive CustomTestStringConvertible {
    public var testDescription: String {
        switch self {
        case .notPurchased:
            "This game has not been purchased."
        case .notInstalled:
            "This game is not currently installed."
        case .parentalControlsDisallowed:
            "This game has been blocked by parental controls."
        }
    }
}
```

Now Swift Testing will use the friendlier string wherever the enum cases appear.

**Important:** This conformance should not be added in production code.


## Writing good verification methods

Verification methods wrap multiple expectations to make other tests easier. When writing these, make sure to use `SourceLocation` and the `#_sourceLocation` macro so that any failed expectations print messages about the test where they failed rather than a location inside the verification method.

**Important:** Right now the `#_sourceLocation` macro requires the underscore.

For example:

```swift
func verifyDivision(_ result: (quotient: Int, remainder: Int), expectedQuotient: Int, expectedRemainder: Int, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(result.quotient == expectedQuotient, sourceLocation: sourceLocation)
    #expect(result.remainder == expectedRemainder, sourceLocation: sourceLocation)
}
```

That can be called from tests elsewhere, and will automatically use the source location of that test rather than the source location of the `#expect` macros used inside `verifyDivision()`.

`#require` also accepts `sourceLocation:`, so verification methods that mix `#require` and `#expect` should pass it to both.
