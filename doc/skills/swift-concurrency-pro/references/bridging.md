# Bridging sync and async code

## Checked continuations

`withCheckedContinuation` and `withCheckedThrowingContinuation` wrap callback-based APIs into async functions. The critical rule is this: **the continuation must be resumed exactly once on every code path.**

- Resuming zero times: the caller hangs forever.
- Resuming twice: a runtime crash.

So, audit every code path. If the callback might not fire (e.g., the object is deallocated), ensure you still resume the continuation.

Default to `withCheckedContinuation` / `withCheckedThrowingContinuation` everywhere, including production builds. The runtime checks catch double-resume and missing-resume bugs that are otherwise extremely hard to diagnose.

Only consider switching to the `withUnsafe` continuation variants after profiling proves the checked version is a bottleneck in a hot path, but this is rare in practice.


## Wrapping delegate-based APIs

For delegate patterns that deliver multiple values over time, use `AsyncStream`. Use `makeStream(of:)` to get the stream and continuation as a pair, and use `onTermination` to clean up when the consumer stops listening.

Make sure that:

- The continuation is stored as a property so delegate callbacks can yield into it.
- `onTermination` runs when the consumer's `for await` loop ends (or the task is cancelled), so it's the right place to stop the underlying service.

This pattern supports a single consumer. If you need multiple consumers, consider broadcasting through an `@Observable` class instead.


## Runtime actor assertions in callback code

Callback-based APIs are a common place for actor assumptions to fail at runtime.

- If a callback reaches main-actor state without carrying that guarantee in the type system, Swift 6 runtime checks can trap instead of silently racing.
- Use `MainActor.assumeIsolated()` only when the callback really is main-actor-bound and you are encoding a guarantee the compiler cannot see.


## `@unchecked Sendable`

This silences the compiler's Sendable checks entirely. It is a promise to the compiler that you have verified thread safety yourself, which is a high bar to clear – evaluate such code very carefully.

Legitimate uses:

- Types that use internal locking (e.g., `os_unfair_lock`, `NSLock`, etc) and are genuinely thread-safe.
- Reference types whose mutable state is protected by an actor in practice but can't express that to the compiler for some reason.

Red flags:

- Applying `@unchecked Sendable` to silence a compiler error without understanding why the error exists. (This was previously a Fix-It suggestion in Xcode, so it’s not uncommon.)
- Applying it to a class with mutable `var` properties and no synchronization.
- Using it as a workaround or shortcut instead of restructuring the code to use value types or actors as appropriate.

Before reaching for `@unchecked Sendable`, check whether Swift 6's region-based isolation already solves the problem – many cases that previously required it now compile cleanly.
