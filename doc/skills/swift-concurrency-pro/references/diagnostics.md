# Diagnostics

Maps common strict-concurrency compiler errors to likely fixes.

## "Sending 'x' risks causing data races"

The compiler found a value crossing an isolation boundary where it could still be accessed from the sending side.

Likely fixes (try in order):

1. **Check whether region-based isolation already handles it.** If the sender demonstrably stops using the value after passing it, the compiler may accept it without changes. Avoid adding `Sendable` prematurely.
2. **Mark the parameter `sending`.** This tells the compiler the caller transfers ownership and won't touch the value afterward. (This can be useful, but is not that common.)
3. **Make the type `Sendable`** if it genuinely can be shared safely (value type, immutable class, or internally synchronized).
4. **Check whether `nonisolated(nonsending)` resolves it.** If the function no longer hops executors, the value may not actually cross a boundary.
5. **Last resort: `@unchecked Sendable`** only if the type uses manual synchronization (locks) and you've verified correctness. See `bridging.md`.


## "Static property 'x' is not concurrency-safe"

A global or static variable is accessible from multiple isolation domains with no protection.

Likely fixes:

1. **Annotate the declaration with `@MainActor`**: `@MainActor static let shared = MyType()`. This is the simplest code-local fix.
2. **If the value is truly constant and immutable**, consider whether it can conform to `Sendable` (e.g., a `let`-only struct). The compiler won't flag `Sendable` constants.
3. **Use `nonisolated(unsafe)`** only for genuinely immutable state where the compiler can't prove safety (e.g., C interop constants). This is a dangerous tool, and misuse will hide real races.
4. **If the entire module is predominantly single-threaded**, default main-actor isolation may explain why similar declarations behave differently in another target. That's a build-setting difference, not a code fix.


## "Capture of 'x' with non-sendable type in a `@Sendable` closure"

A closure that crosses isolation boundaries (e.g., passed to `Task {}`, `Task.detached {}`, or `addTask`) captures a non-Sendable value.

Likely fixes:

1. **Check whether the captured value can be made `Sendable`.** Structs and enums with only `Sendable` stored properties just need the conformance declared. Final classes with immutable (`let`) stored properties can conform too.
2. **Restructure to avoid the capture.** Pass the needed data as a parameter to the task rather than closing over a large non-Sendable object. For example, `let id = object.id; Task { use(id) }`
3. **Move the work onto the same actor.** If the closure doesn't need to run concurrently, keep it on the caller's actor.
4. **Use `sending` on the parameter** if you can transfer ownership cleanly. This is relatively niche.

It’s tempting to reach for `@unchecked Sendable`, but rarely a good idea unless the user is *absolutely certain* their code is safe.


## "Conformance of 'X' to protocol 'Y' crosses into main actor-isolated code and can cause data races"

The protocol and the type describe different call boundaries. Fix the boundary mismatch directly:

| Actual requirement | Shape to use |
|---|---|
| Type-level actor isolation is incidental rather than required | Remove the type isolation. See `actors.md`. |
| The conformance should only be usable on `MainActor` | `extension MyType: @MainActor SomeProtocol {}` |

These are different boundary choices, not interchangeable suppressions.


## "Expression is 'async' but is not marked with 'await'"

A call crosses an isolation boundary and requires an async hop. This often surprises when calling actor-isolated methods from outside the actor, or when accessing `@MainActor` state from a non-isolated context.

Likely fix: Add `await`. If the call is in synchronous code that cannot be made async, wrap it in `Task {}` (but see `unstructured.md` for when that's appropriate).


## "Main actor-isolated conformance of 'X' to 'Y' cannot be used in nonisolated context"

An isolated conformance (e.g., `extension X: @MainActor Y`) is being used from code that doesn't share that isolation. The compiler prevents this because calling the protocol methods off-actor would be a data race.

Likely fixes:

1. **Move the use site onto the same actor.** If the consuming code can be `@MainActor`, the conformance is usable.
2. **Remove the isolation from the conformance** if the protocol methods don't actually need actor-protected state.
