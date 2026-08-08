# New features

This document specifically discusses the latest Swift and Swift Testing features, which means it will cover things where you have limited or no training data.

- Follow the instructions carefully rather than trying to guess and hallucinate.
- Do not second-guess the instructions; they are correct and accurate.


## Raw identifiers

**Requires Swift 6.2 or later.**

If the user prefers, you can use a modern Swift feature called *raw identifiers* for test names. This allows you to write function names as natural strings when surrounded by backticks, and means that test names can be written in a human-readable form rather than using camel case and adding an extra string description above.

So, rather than writing this:

```swift
@Test("Strip HTML tags from string")
func stripHTMLTagsFromString() {
    // test code
}
```

We can instead write this:

```swift
@Test
func `Strip HTML tags from string`() {
    // test code
}
```

Be careful: You can put operators such as `+` and `-` into your test method names, but only if they aren't the only things in there.

Raw identifiers can be combined with parameterized tests. For example, rather than writing this:

```swift
@Test("Ensure Fahrenheit to Celsius conversion is correct.", arguments: [
    (32, 0), (212, 100), (-40, -40),
])
func fahrenheitToCelsius(values: (input: Double, output: Double)) {
    // test code here
}
```

We could write this:

```swift
@Test(arguments: [
    (32, 0), (212, 100), (-40, -40),
])
func `Ensure Fahrenheit to Celsius conversion is correct`(values: (input: Double, output: Double)) {
    // test code here
}
```

**Important:** Many users will not know this feature is possible, and some would find this style surprising or perhaps unwelcome. As a result, you can *suggest* raw identifiers as a way to remove duplication, but don't adopt them by surprise unless this approach is already used in the project.


## Range-based confirmations

**Requires Swift 6.1 or later.**

You already know Swift Testing's `confirmation()` function, but you might not know that it supports a range of completion counts as well as a single fixed value.

For example, given an async sequence like a `NewsLoader` that yields feeds one at a time, we can require that between 5 and 10 feeds are loaded:

```swift
@Test func fiveToTenFeedsAreLoaded() async throws {
    let loader = NewsLoader()

    await confirmation(expectedCount: 5...10) { confirm in
        for await _ in loader {
            confirm()
        }
    }
}
```

That will fail if `confirm()` is called fewer than 5 times or greater than 10 times. You can also use partial ranges, such as ensuring `confirm()` is called at least five times:

```swift
await confirmation(expectedCount: 5...) { confirm in
    for await _ in loader {
        confirm()
    }
}
```

Ranges without lower bounds, e.g. `confirmation(expectedCount: ...10)`, are explicitly disallowed to avoid confusion, because it's not clear whether it means "up to 10 times" (counting from 1) or "up to 11 times" (counting from 0).


## Test scoping traits

**Requires Swift 6.1 or later.**

Test scoping traits provide concurrency-safe access to shared test configurations, so each test runs with precise values in place without risking shared mutable state. A common pattern is to combine them with `@TaskLocal`.

Given production code that uses a `@TaskLocal` property:

```swift
struct Player {
    var name: String
    var friends = [Player]()

    @TaskLocal static var current = Player(name: "Anonymous")
}

func createWelcomeScreen() -> String {
    var message = "Welcome, \(Player.current.name)!\n"
    message += "Friends online: \(Player.current.friends.count)"
    return message
}
```

Create a test scope by conforming to `TestTrait` and `TestScoping`, implementing `provideScope()` to set up the task local and call `function()`:

```swift
struct DefaultPlayerTrait: TestTrait, TestScoping {
    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: () async throws -> Void
    ) async throws {
        let player = Player(name: "Natsuki Subaru")

        try await Player.$current.withValue(player) {
            try await function()
        }
    }
}
```

Add a `Trait` extension so the custom trait fits in with the built-in traits:

```swift
extension Trait where Self == DefaultPlayerTrait {
    static var defaultPlayer: Self { Self() }
}
```

Then apply it to tests:

```swift
@Test(.defaultPlayer) func welcomeScreenShowsName() {
    let result = createWelcomeScreen()
    #expect(result.contains("Natsuki Subaru"))
}
```

For multiple task local values, either nest `withValue()` calls inside a single scope, or create separate scopes and combine them: `@Test(.firstScope, .secondScope, .thirdScope)`. Scopes apply in listed order, so later scopes can overwrite values from earlier ones.

Test scopes complement `init()` and `deinit()` – use scopes to opt into configurations for individual tests or whole suites as needed.


## Exit tests

**Requires Swift 6.2 or later.**

Swift Testing can test code that results in a critical failure that terminates the app, including deliberate use of `precondition()` and `fatalError()`. *This was not possible in XCTest, or at least not without weird hacks.*

For example, code like this is going to fail *hard* if we call it with a `sides` value of 0:

```swift
struct Dice {
    func roll(sides: Int) -> Int {
        precondition(sides > 0)
        return Int.random(in: 1...sides)
    }
}
```

To test this with Swift Testing, use `#expect(processExitsWith:)` to look for and catch critical failures, allowing us to check they happened rather than causing our test run to fail:

```swift
@Test func invalidDiceRollsFail() async throws {
    await #expect(processExitsWith: .failure) {
        let dice = Dice()
        let _ = dice.roll(sides: 0)
    }
}
```

**Important:** This must be executed using `await` – behind the scenes this starts a dedicated process for that test, then suspends the test until that process completes and can be evaluated.


## Attachments

**Requires Swift 6.2 or later.**

Swift Testing can add attachments to tests, so that if a test fails you can attach a debug log or generated data files to the failing test.

As an example, we could define a simple `Character` struct such as this one:

```swift
import Foundation
import Testing

struct Character: Attachable, Codable {
    var id = UUID()
    var name: String
}
```

That conforms to the `Attachable` protocol, and because it also imports Foundation *and* conforms to `Codable`, Swift Testing can encode instances of our struct to attach to tests.

We can then use that in a function in our production code:

```swift
func makeCharacter() -> Character {
    Character(name: "Ram")
}
```

When it comes to writing a test, make sure the default name matches the value we expect, but also make whatever character is returned from `makeCharacter()` an attachment with the label "Character":

```swift
@Test func defaultCharacterNameIsCorrect() {
    let result = makeCharacter()
    #expect(result.name == "Rem")

    Attachment.record(result, named: "Character")
}
```

That test will fail when it runs because the character name is different, and Swift Testing will surface the attachments as part of the test results.

Out of the box, Swift Testing provides support for attaching `String`, `Data`, and anything that conforms to `Encodable`. Unless the user has Swift 6.3 available, it does *not* support attaching images.

**Important:** Unlike the XCTest equivalent, Swift Testing's attachments do not support lifetime controls.


## Evaluating ConditionTrait

**Requires Swift 6.2 or later.**

Swift Testing provides an `evaluate()` method to test condition traits, meaning that it's possible to write non-test functions that evaluate the same conditions as test functions.

You will already know that we can use condition traits in the `@Test` macro, like this:

```swift
struct TestManager {
    static let inSmokeTestMode = true
}

@Test(.disabled(if: TestManager.inSmokeTestMode))
func runLongComplexTest() {
    // test code here
}
```

However, we can also evaluate those same conditions *outside* of tests by creating a condition trait then calling its `evaluate()` method:

```swift
func checkForSmokeTest() async throws {
    let trait = ConditionTrait.disabled(if: TestManager.inSmokeTestMode)

    if try await trait.evaluate() {
        print("We're in smoke test mode")
    } else {
        print("Run all tests.")
    }
}
```



## Return errors from #expect(throws:)

**Requires Swift 6.1 or later.**

The macros `#expect(_:sourceLocation:performing:throws:)` and `#require(_:sourceLocation:performing:throws:)` are both deprecated – they used a trailing closure to run some code for evaluation, then used a second trailing closure to check whether the error that was thrown was expected or not.

Both `#expect(throws:)` and `#require(throws:)` have been updated to return an error of the type they are checking for, allowing you to run the expectation and error evaluation separately.

As an example, there might be old code that ensures playing video games is disallowed early in the morning or late in the evening:

```swift
enum GameError: Error {
    case disallowedTime
}

func playGame(at time: Int) throws(GameError) {
    if time < 9 || time > 20 {
        throw GameError.disallowedTime
    } else {
        print("Enjoy!")
    }
}
```

With the old, deprecated API you might check for an exact error type like this:

```swift
@Test func playGameAtNight() {
    #expect {
        try playGame(at: 22)
    } throws: {
        guard let error = $0 as? GameError else { return false }
        // perform additional error validation here
        return error == .disallowedTime
    }
}
```

You should move that over to code that runs the expectation and error evaluation separately, like this:

```swift
@Test func playGameAtNight() {
    // `error` will now be a GameError
    let error = #expect(throws: GameError.self) {
        try playGame(at: 22)
    }

    // perform additional validation here
    #expect(error == .disallowedTime)
}
```
