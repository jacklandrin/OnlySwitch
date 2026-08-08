# Core rules

Swift Testing is still very new compared to XCTest, which means the majority of projects will use XCTest, and also the majority of your training data is based on XCTest.

This guide provides core rules you must always follow to ensure you're making natural, idiomatic use of Swift Testing, and not just reskinning XCTest based on old training data.

**Important:** At this time, Swift Testing does *not* support UI tests, so XCTest must be used there.

- When organizing test suites, prefer structs over classes. You *can* use classes, but structs are preferred unless you need subclassing or deinitializers.
- Agents frequently add `@Suite` to every test struct. This is unnecessary: any type that contains `@Test` methods is automatically treated as a test suite. You only need `@Suite` explicitly when you want to name it or attach traits, e.g. `@Suite(.tags(.networking))`.
- You shouldn't use the old `setUp()`/`tearDown()` approach of XCTest. You can simply use `init()` in structs, `init()` and `deinit()` in classes, or test scopes for more advanced situations. For example:

    ```swift
    struct PlayerTests {
        let sut: Player

        init() {
            sut = Player(name: "Natsuki Subaru")
        }

        @Test func nameIsCorrect() {
            #expect(sut.name == "Natsuki Subaru")
        }
    }
    ```
- All test suites must have an initializer that expects no parameters, so they can be called by tests inside that suite. If any properties are added to a test suite, they must either have default values, or you must add a custom initializer that sets values for them.
- Test suite initializers can be marked `async` and/or `throws`, as can all tests.
- With Swift Testing there is never a need to use `XCTestCase` or any form of `XCTAssert` in any unit or integration test.
- You do *not* need to prefix test methods with `test`. For example, you can use `userCanLogOut()` rather than `testUserCanLogOut`.
- Random, parallel test execution is standard on Swift Testing, so each test must be written to execute in any order at any time.
- Parameterized tests are extremely powerful and allow tests to cover a wider range of ground without the code greatly expanding, so prefer them where possible. However, be careful: they take at most two argument collections, and two collections form a Cartesian product rather than pairwise zipping, so the number of combinations produced can grow quickly. If you need pairwise zipping of two collections, pass `zip(collection1, collection2)` as the `arguments` value.
- Swift Testing supports `@available` on individual tests, but *not* on test suites. So, if a suite (for example) solely contains tests written for iOS 26, place `@available(iOS 26, *)` on each individual test and *not* on the whole suite.
- If a test executes without reaching any `#expect` or `#require`, it is assumed to have passed.
- You should use `withKnownIssue` to wrap code with a known bug – it expects a test failure to occur, and *fails* the test if no issue is recorded. Adding `isIntermittent: true` changes the semantics: the test passes if no issue is recorded, but marks an expected failure if one is, making it useful for flaky issues you're actively debugging.
- Never use `!` to negate Booleans in `#expect` or `#require`, because it defeats Swift Testing’s macro expansion. So, `#expect(!isLoggedIn)` is bad and will report unhelpful results on failure, whereas `#expect(isLoggedIn == false)` is good, and will be evaluated properly in case the expectation fails.

Finally, use `@Tag` to create custom Swift Testing tags like this:

```swift
extension Tag {
    @Tag static var networking: Self
}
```

Tags let you categorize tests across suites, so you can run or filter by tag regardless of where the tests live. Apply them using `@Test(.tags(.networking))` on individual tests or on a whole suite with `@Suite(.tags(.networking))`. For example:

```swift
@Test(.tags(.networking))
func fetchUserProfile() async throws {
    // test code here
}
```
