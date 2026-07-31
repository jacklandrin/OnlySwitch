---
name: swift-concurrency-pro
description: Reviews Swift code for concurrency correctness, modern API usage, and common async/await pitfalls. Use when reading, writing, or reviewing Swift concurrency code.
license: MIT
metadata:
  author: Paul Hudson
  version: "1.0"
---

Review Swift concurrency code for correctness, modern API usage, and adherence to project conventions. Report only genuine problems - do not nitpick or invent issues.

Review process:

1. Scan for known-dangerous patterns using `references/hotspots.md` to prioritize what to inspect.
1. Check for recent Swift 6.2 concurrency behavior using `references/new-features.md`.
1. Validate actor usage for reentrancy and isolation correctness using `references/actors.md`.
1. Ensure structured concurrency is preferred over unstructured where appropriate using `references/structured.md`.
1. Check unstructured task usage for correctness using `references/unstructured.md`.
1. Verify cancellation is handled correctly using `references/cancellation.md`.
1. Validate async stream and continuation usage using `references/async-streams.md`.
1. Check bridging code between sync and async worlds using `references/bridging.md`.
1. Review any legacy concurrency migrations using `references/interop.md`.
1. Cross-check against common failure modes using `references/bug-patterns.md`.
1. If the project has strict-concurrency errors, map diagnostics to fixes using `references/diagnostics.md`.
1. If reviewing tests, check async test patterns using `references/testing.md`.

If doing a partial review, load only the relevant reference files.


## Core Instructions

- Target Swift 6.2 or later with strict concurrency checking.
- If code spans multiple targets or packages, compare their concurrency build settings before assuming behavior should match.
- Prefer structured concurrency (task groups) over unstructured (`Task {}`).
- Prefer Swift concurrency over Grand Central Dispatch for new code. GCD is still acceptable in low-level code, framework interop, or performance-critical synchronous work where queues and locks are the right tool – don't flag these as errors.
- If an API offers both `async`/`await` and closure-based variants, always prefer `async`/`await`.
- Do not introduce third-party concurrency frameworks without asking first.
- Do not suggest `@unchecked Sendable` to fix compiler errors. It silences the diagnostic without fixing the underlying race. Prefer actors, value types, or `sending` parameters instead. The only legitimate use is for types with internal locking that are provably thread-safe.


## Output Format

Organize findings by file. For each issue:

1. State the file and relevant line(s).
2. Name the rule being violated.
3. Show a brief before/after code fix.

Skip files with no issues. End with a prioritized summary of the most impactful changes to make first.

Example output:

### DataLoader.swift

**Line 18: Actor reentrancy – state may have changed across the `await`.**

```swift
// Before
actor Cache {
    var items: [String: Data] = [:]

    func fetch(_ key: String) async throws -> Data {
        if items[key] == nil {
            items[key] = try await download(key)
        }
        return items[key]!
    }
}

// After
actor Cache {
    var items: [String: Data] = [:]

    func fetch(_ key: String) async throws -> Data {
        if let existing = items[key] { return existing }
        let data = try await download(key)
        items[key] = data
        return data
    }
}
```

**Line 34: Use `withTaskGroup` instead of creating tasks in a loop.**

```swift
// Before
for url in urls {
    Task { try await fetch(url) }
}

// After
try await withThrowingTaskGroup(of: Data.self) { group in
    for url in urls {
        group.addTask { try await fetch(url) }
    }

    for try await result in group {
        process(result)
    }
}
```

### Summary

1. **Correctness (high):** Actor reentrancy bug on line 18 may cause duplicate downloads and a force-unwrap crash.
2. **Structure (medium):** Unstructured tasks in loop on line 34 lose cancellation propagation.

End of example.


## References

- `references/hotspots.md` - Grep targets for code review: known-dangerous patterns and what to check for each.
- `references/new-features.md` - Swift 6.2 changes that alter review advice: default actor isolation, isolated conformances, caller-actor async behavior, `@concurrent`, `Task.immediate`, task naming, and priority escalation.
- `references/actors.md` - Actor reentrancy, shared-state annotations, global actor inference, and isolation patterns.
- `references/structured.md` - Task groups over loops, discarding task groups, concurrency limits.
- `references/unstructured.md` - Task vs Task.detached, when Task {} is a code smell.
- `references/cancellation.md` - Cancellation propagation, cooperative checking, broken cancellation patterns.
- `references/async-streams.md` - AsyncStream factory, continuation lifecycle, back-pressure.
- `references/bridging.md` - Checked continuations, wrapping legacy APIs, `@unchecked Sendable`.
- `references/interop.md` - Migrating from GCD, `Mutex`/locks, completion handlers, delegates, and Combine.
- `references/bug-patterns.md` - Common concurrency failure modes and their fixes.
- `references/diagnostics.md` - Strict-concurrency compiler errors, protocol conformance fixes, and likely remedies.
- `references/testing.md` - Async test strategy with Swift Testing, race detection, avoiding timing-based tests.
