# Hotspots

Search targets for concurrency review. When any of these appear in code, inspect carefully using the referenced rules.

## `DispatchQueue`

In app-level code, `DispatchQueue.main.async`, `DispatchQueue.global()`, and custom serial queues usually have a Swift concurrency equivalent – see `interop.md`. However, GCD can still be appropriate in low-level libraries, framework interop, and performance-critical synchronous sections where queues or locks are the right tool. Check the context carefully before flagging.


## `Task.detached`

Rarely correct. Usually means the author wanted background execution but should have used `@concurrent` (Swift 6.2) or a task group. Check whether shedding actor isolation and priority is truly intentional. See `unstructured.md`.


## `Task {}` inside a loop

Frequently a bad idea – evaluate whether it should be a task group instead. See `structured.md`.


## `withCheckedContinuation` / `withCheckedThrowingContinuation`

Audit every code path to ensure the continuation is resumed exactly once. Watch for early returns, thrown errors, and callbacks that might never fire. See `bridging.md`.


## `AsyncStream` (closure-based initializer)

Prefer the modern `AsyncStream.makeStream(of:)` factory. If using the closure form, verify the continuation is finished in all cleanup paths. See `async-streams.md`.


## `@unchecked Sendable`

Should be very rare. Check whether the type actually provides thread safety (internal locking, immutability). If it was added just to silence a compiler error, the real fix is usually an actor or value type. Check whether Swift 6 region-based isolation makes it unnecessary. See `bridging.md`.


## `MainActor.run {}`

Often unnecessary. If the surrounding code is already `@MainActor` (explicitly or via default isolation), this is a no-op. If it's used to hop to the main actor from a background context, check whether the function should just be `@MainActor` instead.


## Actors

Check for reentrancy bugs: any method that reads state, awaits, then writes state is suspect. See `actors.md` and `bug-patterns.md`.


## Force unwraps after `await` inside actors

A `!` on actor state after an `await` is a prime target for a latent crash, because another caller may have set the value to `nil` during the suspension. See `bug-patterns.md`.
