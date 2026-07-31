# Async streams

## Prefer `makeStream(of:)` factory

The modern way to create an `AsyncStream` is the static factory method, which returns both the stream and its continuation as a tuple. This avoids capturing the continuation in a closure.

```swift
// OLD: Closure-based, awkward to store the continuation.
var continuation: AsyncStream<Event>.Continuation?
let stream = AsyncStream<Event> { cont in
    continuation = cont
}

// NEW: Clean, no closure capture needed.
let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
```

This also works with `AsyncThrowingStream.makeStream(of:throwing:)`.


## Continuation lifecycle

A continuation must always be finished exactly once. Failing to finish it causes the consumer's `for await` loop to hang indefinitely. Finishing it twice is a programmer error (although `AsyncStream.Continuation` tolerates it, `CheckedContinuation` does not).

Always finish in cleanup paths:

```swift
let (stream, continuation) = AsyncStream.makeStream(of: Event.self)

let monitor = NetworkMonitor()

monitor.onEvent = { event in
    continuation.yield(event)
}

monitor.onComplete = {
    continuation.finish()
}

// If the monitor can be deallocated before completing:
continuation.onTermination = { _ in
    monitor.stop()
}
```


## Buffering and back pressure

`AsyncStream` has a default buffer of unlimited size. For high-throughput producers, this can cause unbounded memory growth. Specify a buffering policy:

```swift
let (stream, continuation) = AsyncStream.makeStream(
    of: SensorReading.self,
    bufferingPolicy: .bufferingNewest(100)
)
```

Choose from:

- `.bufferingNewest(n)` keeps the most recent `n` elements, dropping older ones.
- `.bufferingOldest(n)` keeps the first `n` elements, dropping newer ones.
- `.unbounded` is the default; use only when the consumer keeps up.


## `for await` and cancellation

A `for await` loop automatically stops when the task is cancelled or the stream finishes. You do not need to manually check cancellation inside the loop – but code *after* the loop does run, so handle cleanup there if needed.
