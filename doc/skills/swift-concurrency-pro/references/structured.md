# Structured concurrency

## `async let` vs task groups

Use `async let` when you have a fixed number of independent operations that return different types, e.g. fetching the news, the weather, and an app update at the same time. Use task groups when you have a dynamic number of operations of the same type, e.g. downloading all images in an array of URLs.


## Task groups over loops

It’s generally a bad idea to use unstructured tasks in a loop; prefer task groups.

```swift
// WRONG: No cancellation propagation, no way to await all results, leaked tasks on failure.
for url in urls {
    Task { try await fetch(url) }
}

// RIGHT: Structured, cancellable, collects results.
let results = try await withThrowingTaskGroup { group in
    for url in urls {
        group.addTask { try await fetch(url) }
    }

    var collected = [Data]()
    for try await result in group {
        collected.append(result)
    }
    return collected
}
```


## `withDiscardingTaskGroup` (Swift 5.9+)

When child tasks don't return meaningful results (fire-and-forget), use `withDiscardingTaskGroup` instead of `withTaskGroup`. It avoids accumulating unused results in memory.

```swift
// Preferred for side-effect-only child tasks
await withDiscardingTaskGroup { group in
    for connection in connections {
        group.addTask { await connection.sendHeartbeat() }
    }
}
```


## Limiting concurrency

Task groups launch all child tasks eagerly, which may be undesirable. Consider limiting concurrency manually when it is appropriate:

```swift
try await withThrowingTaskGroup { group in
    let maxConcurrent = 4
    var iterator = urls.makeIterator()

    // Start initial batch
    for _ in 0..<maxConcurrent {
        guard let url = iterator.next() else { break }
        group.addTask { try await fetch(url) }
    }

    // As each finishes, start the next
    for try await result in group {
        process(result)
        if let url = iterator.next() {
            group.addTask { try await fetch(url) }
        }
    }
}
```


## Error handling with partial results

When one child task throws, the group cancels all remaining children. If you need partial results, catch errors inside each child task:

```swift
await withTaskGroup(of: (URL, Result<Data, Error>).self) { group in
    for url in urls {
        group.addTask {
            do {
                return (url, .success(try await fetch(url)))
            } catch {
                return (url, .failure(error))
            }
        }
    }

    for await (url, result) in group {
        switch result {
        case .success(let data): handle(data)
        case .failure(let error): log(error, for: url)
        }
    }
}
```


## Inferring the type of task groups

Swift is usually able to infer the type of task groups, but not always. Simple types like `String`, `URL`, `Data`, etc, usually work fine, but the example above uses `withTaskGroup(of: (URL, Result<Data, Error>).self)` and that is an example of the specific type being required – Swift would not be able to infer that.
