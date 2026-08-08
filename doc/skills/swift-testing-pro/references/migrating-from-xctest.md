# Migrating from XCTest

If the project has existing tests written using XCTest, do *not* rewrite to Swift Testing unless requested. Even then, remember that XCTest supports UI testing, whereas Swift Testing does not.

Most things in XCTest have a direct equivalent in Swift Testing:

- `XCTAssertEqual(a, b)` maps to `#expect(a == b)`
- `XCTAssertLessThan(a, b)` maps to `#expect(a < b)`
- `XCTAssertThrowsError` maps to `#expect(throws:)`
- `XCTUnwrap(optional)` maps to `try #require(optional)` – both unwrap or fail, but `#require` works with any Boolean condition too.
- `XCTFail("message")` maps to `Issue.record("message")` – use this to manually record a test failure.
- `XCTAssertIdentical(a, b)` maps to `#expect(a === b)` – for checking two references point to the same object instance.

…and so on.

However, Swift Testing does *not* offer built-in float tolerance when checking if two floating-point values are *close enough* to be considered the same.

To do that, you must bring in Apple's Swift Numerics library and use its `isApproximatelyEqual(to:absoluteTolerance:)` method like this:

```swift
#expect(celsius.isApproximatelyEqual(to: 0, absoluteTolerance: 0.000001))
```

**Important:** Unless it is already imported into the project, do *not* add Swift Numerics as a library without first requesting permission from the user.


## Converting from XCTest to Swift Testing

If you are tasked with converting XCTest code to Swift Testing, you should:

1. Start by keeping the same broad structure: the same type names (just going from a class to a struct), and the same test methods (just removing `test` from the names and using `@Test` instead), switching from old-style assertions to new-style expectations.
2. Look for places where parameterized tests can either cut down on test code or improve coverage.
3. Add any appropriate `#require` checks at the start of tests, for preconditions.
4. Finish by adding traits where appropriate – `.timeLimit()`, `.enabled(if:)`, `.tags()`, etc, to replace XCTest conventions such as skipping tests.
