# Interop and migration

Approved patterns for migrating legacy concurrency mechanisms to Swift concurrency.

## Completion handlers → `async`/`await`

Unless the user requested you to modernize their code, it’s better to leave existing completion handler code alone because it’s understood, tested, and mature.

Instead, provide modern Swift concurrency wrappers for it using `withCheckedThrowingContinuation`. Resume exactly once on every path. See `bridging.md` for detailed rules.

```swift
func loadUser(id: String) async throws -> User {
    try await withCheckedThrowingContinuation { continuation in
        api.fetchUser(id: id) { result in
            continuation.resume(with: result)
        }
    }
}
```

If the SDK already provides an async overload, use it directly instead of wrapping.


## Delegates → `AsyncStream`

Delegates that deliver multiple values over time map well to `AsyncStream`. Use `makeStream(of:)` and yield from delegate callbacks. See `bridging.md` for the full pattern.

Single-shot delegates (one callback, then done) can use `withCheckedContinuation` instead.


## `DispatchQueue.main.async` → `@MainActor`

```swift
// Before
DispatchQueue.main.async {
    self.label.text = "Done"
}

// After – make the enclosing function or type @MainActor
@MainActor
func updateLabel() {
    label.text = "Done"
}
```

If called from a non-isolated async context, the `await` at the call site replaces the dispatch:

```swift
await updateLabel()
```


## `DispatchQueue.global().async` → `@concurrent` or Task Group

For one-off background work:

```swift
// Before
DispatchQueue.global().async {
    let result = heavyComputation()
    DispatchQueue.main.async { self.result = result }
}

// After (Swift 6.2)
@concurrent
func heavyComputation() async -> ComputationResult { ... }

// At call site:
self.result = await heavyComputation()
```

A plain `async` helper does not offload CPU work by itself. If the goal is to leave the caller's executor, make that explicit.

For parallel batch work, use `withTaskGroup`. See `structured.md`.


## Serial `DispatchQueue` → `actor`

A serial dispatch queue protecting mutable state maps directly to an `actor`:

```swift
// Before
class TokenStore {
    private let queue = DispatchQueue(label: "token-store")
    private var token: String?

    func setToken(_ t: String) {
        queue.sync { token = t }
    }

    func getToken() -> String? {
        queue.sync { token }
    }
}

// After
actor TokenStore {
    private var token: String?

    func setToken(_ t: String) { token = t }
    func getToken() -> String? { token }
}
```


## Locks and checked sendability

If the API must stay synchronous, prefer a lock over introducing actor isolation just to serialize access.

- `Mutex` gives the best compile time and can preserve checked `Sendable` on the owning type.
- Traditional locks still work, but the owning reference type often ends up with `@unchecked Sendable`.

*Choose an actor only when the API itself should become actor-isolated.*


## Moving from Combine to `AsyncSequence`

| Combine | Swift Concurrency |
|---------|-------------------|
| `publisher.sink { }` | `for await value in stream { }` |
| `publisher.map { }` | `stream.map { }` |
| `publisher.filter { }` | `stream.filter { }` |
| `PassthroughSubject` | `AsyncStream` via `makeStream(of:)` |
| `CurrentValueSubject` | No direct equivalent (see note below) |
| `publisher.values` | Already an `AsyncSequence` – use directly |

If a Combine publisher already exposes a `.values` property, consume that directly rather than wrapping it in a new `AsyncStream`.

Combine is not officially deprecated at this time, but Apple’s advice is to avoid using it.
