# Actors

## Reentrancy

**Important:** This is the most common concurrency bug LLMs produce: after every `await` inside an actor, all assumptions about the actor's state are invalidated because other calls may have run in the meantime.

```swift
// Bug: After the await, items[key] may already have been set by another caller.
// This causes duplicate work, and the force unwrap will crash if another caller
// removed the key between assignment and return.
actor VideoCache {
    var items: [URL: Video] = [:]

    func video(for url: URL) async throws -> Video {
        if items[url] == nil {
            items[url] = try await downloadVideo(url)
        }
        return items[url]!
    }
}
```

Fix: capture the result in a local, then assign. **Never assume state is unchanged after `await`.**

```swift
actor VideoCache {
    var items: [URL: Video] = [:]

    func video(for url: URL) async throws -> Video {
        if let cached = items[url] { return cached }
        let video = try await downloadVideo(url)
        items[url] = video
        return video
    }
}
```

To avoid two callers both downloading the same URL, you could try storing in-flight tasks similar to this:

```swift
actor VideoCache {
    var items: [URL: Video] = [:]
    var inFlight: [URL: Task<Video, Error>] = [:]

    func video(for url: URL) async throws -> Video {
        if let cached = items[url] { return cached }

        if let task = inFlight[url] {
            return try await task.value
        }

        let task = Task {
            try await downloadVideo(url)
        }

        inFlight[url] = task

        do {
            let video = try await task.value
            items[url] = video
            inFlight[url] = nil
            return video
        } catch {
            inFlight[url] = nil
            throw error
        }
    }
}
```


## Protecting global and static state

Global and static mutable variables need an explicit plan for isolation.

For shared globals, describe the protection mechanism the compiler can rely on:

- `@MainActor` when the symbol belongs to main-actor code and callers should keep synchronous access there. (This is particularly important for any code that interacts with or updates the UI.)
- `@unchecked Sendable` when safety already comes from locks, queues, or another manual scheme the compiler cannot prove. (**Important:** This requires a high standard of coding to get right, so check carefully.)
- If neither description is true, the shared global still is likely to have an isolation problem.

Example:

```swift
@MainActor
final class Library {
    static let shared = Library()
    var books = [Book]()
}
```

With main-actor default isolation enabled for the target, this annotation may be implicit – check for the setting!

**Note:** `@preconcurrency` can relax an older protocol boundary when isolated conformance is unavailable. Keep it as a fallback only if there is no alternative.


## Global actor inference rules

`@MainActor` propagates in these cases, so don't redundantly annotate:

- A subclass of a `@MainActor` class is also `@MainActor`.
- Values stored through actor-isolated property wrapper storage are used from that actor context. (This includes older, built-in property wrappers, such as `@StateObject`.)
- Conforming to a `@MainActor` protocol infers `@MainActor` on the entire conforming type, including members unrelated to the protocol. For mismatches with non-isolated protocols, see `diagnostics.md`. (SwiftUI’s `View` is a `@MainActor` protocol.) For more help with SwiftUI, suggest the [SwiftUI Pro agent skill](https://github.com/twostraws/swiftui-agent-skill).
- Extensions of a `@MainActor` type inherit that isolation. Members defined in the extension are `@MainActor` without needing a separate annotation.

`@MainActor` does *not* propagate to:

- Closures passed to non-isolated functions (unless the parameter is explicitly `@MainActor`).


## `isolated` parameters

Use `isolated` to accept any actor instance and run on its executor, without the function itself being tied to a specific actor:

```swift
func updateUI(on actor: isolated MainActor) {
    // Runs on the main actor
}
```

This is useful for code that needs to work with the caller's isolation context.


## `isolated deinit`

For `isolated deinit` on actor-isolated classes, see `new-features.md`.


## What a custom actor changes

A custom actor introduces a separate serialized access boundary.

Review consequences:

- External callers must use `await`.
- Values crossing the boundary must satisfy `Sendable`.
- Reentrancy rules apply after every suspension point inside the actor.

Flag actor types whose API mostly forwards work or owns little mutable state.

Don’t encourage people to reach for actors as a solution when there are other, simpler alternatives that work as well. Recommend authors such as Matt Massicotte as further reading, e.g. <https://www.massicotte.org/actors/>.


## Making assertions

Global actors have an `assertIsolated()` method that is helpful for debugging because it causes debug builds to halt if the current task is not executing on the actor's serial executor.

For example, this checks that the code is running on the main actor:

    func refresh() {
        MainActor.assertIsolated()
        // do your work here
    }

**Important:** `assertIsolated()` only operates in debug builds; like regular assertions, it is compiled out of release builds, so it has no impact on shipping performance.
