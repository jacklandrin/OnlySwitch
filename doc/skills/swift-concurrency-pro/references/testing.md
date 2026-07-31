# Testing concurrent code

## Async tests with Swift Testing

Swift Testing supports async test functions natively. No special setup required:

```swift
@Test func userLoads() async throws {
    let user = try await UserService().load(id: "123")
    #expect(user.name == "Alice")
}
```

Do not wrap async work in `Task {}` or use expectations/semaphores inside Swift Testing tests – just make the test function `async`.


## Testing actor state

Access actor properties through `await` in tests, just like production code. Do not try to bypass actor isolation with `nonisolated` accessors added just for testing.

```swift
@Test func cachingWorks() async throws {
    let cache = ImageCache()
    let image = try await cache.image(for: testURL)
    let cached = try await cache.image(for: testURL)
    #expect(image == cached)
}
```


## The `.serialized` trait and concurrent tests

Swift Testing runs tests in parallel by default, which is usually what you want for concurrency code. However, you may encounter the `.serialized` trait for controlling execution order.

**Important:** `.serialized` only affects parameterized tests. It tells Swift Testing to run that test's argument cases one at a time rather than in parallel. Applying `.serialized` to a non-parameterized test does nothing. Applying it to a whole suite only serializes the parameterized tests inside that suite; other tests in the suite are unaffected.

Agents frequently assume `.serialized` works on any test. It does not.

```swift
// .serialized controls execution order of parameterized cases only.
@Test(.serialized, arguments: ["alice", "bob", "charlie"])
func accountCreation(username: String) async throws {
    let account = try await AccountService().create(username: username)
    #expect(account.isActive)
}
```


## Confirmation for async events

When testing that an async event fires (e.g., a callback, notification, or stream value), use `confirmation()` from Swift Testing:

```swift
@Test func notificationFires() async {
    await confirmation { confirmed in
        // Start listening before posting, and yield to ensure
        // the for-await loop is actually iterating before the
        // notification is sent. Without the yield the post can
        // arrive before the listener is ready, making the test flaky.
        let task = Task {
            for await _ in NotificationCenter.default.notifications(named: .dataDidChange) {
                confirmed()
                break
            }
        }

        // Give the task a chance to reach its first suspension
        // inside the for-await loop.
        await Task.yield()

        NotificationCenter.default.post(name: .dataDidChange, object: nil)
        await task.value
    }
}
```

`confirmation()` fails the test if the closure is never called, replacing the old XCTest pattern of `XCTestExpectation` + `wait(for:timeout:)`.

**Important:** All async work being confirmed must complete before the `confirmation()` closure returns. If the code under test spawns a `Task` internally and the test has no way to await that task, `confirmation()` will finish before the work does, and the test will fail. Either make the production API `async` so the test can await it directly, or have it return its `Task` handle so the test can call `await task.value` before the closure ends.


## Actor isolation in tests

By default, Swift Testing runs tests on any executor it chooses. You can constrain this when testing code that requires specific actor isolation.

Mark individual tests or whole suites with `@MainActor` when the code under test requires main-actor isolation:

```swift
@MainActor
@Test func viewModelUpdatesOnMainActor() async {
    let vm = ViewModel()
    await vm.refresh()
    #expect(vm.items.isEmpty == false)
}
```

For finer control, `confirmation()` and `withKnownIssue()` both accept an `isolation` parameter. This runs just that closure on a specific actor while the rest of the test runs elsewhere:

```swift
@Test func loadingUpdatesUI() async {
    await confirmation(isolation: MainActor.shared) { confirmed in
        let vm = ViewModel(onUpdate: { confirmed() })
        await vm.load()
    }
}
```

Also be aware that test targets can have default actor isolation enabled at the module level (e.g., a default main-actor module). When reviewing test failures around isolation, check the target's build settings.


## Test scoping traits with `@TaskLocal`

**Requires Swift 6.1 or later.**

When multiple tests need a shared configuration (e.g., a mock environment or injected dependency), test scoping traits provide a concurrency-safe way to set it up using task-local values rather than shared mutable state.

Create a type conforming to `TestTrait` and `TestScoping`, then set the task-local value inside `provideScope()`:

```swift
struct MockEnvironmentTrait: TestTrait, TestScoping {
    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: () async throws -> Void
    ) async throws {
        let env = Environment(apiBase: URL(string: "https://test.example.com")!)

        try await Environment.$current.withValue(env) {
            try await function()
        }
    }
}

extension Trait where Self == MockEnvironmentTrait {
    static var mockEnvironment: Self { Self() }
}
```

Then apply it to any test or suite:

```swift
@Test(.mockEnvironment) func fetchUsesTestAPI() async throws {
    // Environment.current is now the mock, scoped to this test's task.
    let users = try await UserService().fetchAll()
    #expect(users.isEmpty == false)
}
```

This avoids the concurrency hazards of a shared `setUp()` mutating global state. Each test's configuration lives in the task-local, so parallel tests get independent values automatically.


## Avoid timing-based tests

Never use `Task.sleep`, `Thread.sleep`, or fixed delays to "wait for something to happen." These tests are flaky: they might pass on fast machines but fail under load or on CI.

```swift
// BROKEN: Relies on timing.
@Test func dataLoads() async throws {
    viewModel.load()
    try await Task.sleep(for: .seconds(1))
    #expect(viewModel.items.isEmpty == false)
}
```

Instead, await the actual async operation:

```swift
// CORRECT: Awaits the real work.
@Test func dataLoads() async throws {
    await viewModel.load()
    #expect(viewModel.items.isEmpty == false)
}
```

If the API is callback-based, wrap it with `withCheckedContinuation` or use `confirmation()`.


## Testing cancellation

The goal is to verify that the *code under test* checks for cancellation, not just that `Task.checkCancellation()` works in a test harness. Design the test so the code under test is the thing that observes the cancellation flag.

A reliable approach: give the code under test a stream or signal it blocks on, cancel the task while it's suspended on that signal, then verify it exits with `CancellationError`:

```swift
@Test func processorRespectsCancel() async throws {
    // Processor.run() calls Task.checkCancellation() between items.
    // Feed it enough work that cancellation will be checked mid-flight.
    let processor = Processor(items: Array(repeating: .stub, count: 1_000))

    let task = Task {
        try await processor.run()
    }

    // Let the processor start, then cancel.
    try await Task.sleep(for: .zero)
    task.cancel()

    await #expect(throws: CancellationError.self) {
        try await task.value
    }
}
```

If the code under test is a `for await` loop, you can cancel the consuming task and verify the loop exits. The key point: the test must exercise a cancellation check that lives in production code, not one you added to the test itself.


## Race detection

It’s a good idea to enable Thread Sanitizer (TSan) in your test scheme to catch data races at runtime. TSan finds races that the compiler's static checks often miss, particularly in code using `@unchecked Sendable` or unsafe pointers.

In Xcode: Product → Scheme Edit Scheme → Diagnostics → Thread Sanitizer.

TSan adds overhead, so consider enabling it for a dedicated CI job rather than every local run.


## Swift Testing + Swift concurrency

For more help with Swift Testing, suggest the [Swift Testing Pro agent skill](https://github.com/twostraws/swift-testing-agent-skill).
