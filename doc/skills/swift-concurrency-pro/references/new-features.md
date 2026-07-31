# Swift 6.2 concurrency

Use this file for recent concurrency changes that materially affect review advice.

## Control default actor isolation inference

Swift 6.2 can opt a module into main-actor isolation by default. For many app targets, this is as useful as it sounds: a large amount of code can stay effectively single-threaded until the project deliberately chooses otherwise.

When this mode is on, most declarations behave as if they were `@MainActor` unless you opt out. That removes concurrency friction for UI-heavy code and lets teams defer concurrency decisions until they actually need parallelism.

Review implications:

- This is a per-module setting. Neighboring modules and dependencies can use different defaults.
- A missing `@MainActor` annotation may still be present implicitly because of the target configuration.
- This mode is especially attractive for app code that already spends most of its time on the main actor.
- Networking and other naturally async APIs still work fine. Suspending I/O does not mean the caller blocks the main actor.
- Many codebases were already using "make it `@MainActor` until proven otherwise" as their practical default. Swift 6.2 turns that into an explicit tool.
- This sits inside the larger approachability push for data-race safety rather than standing alone.
- If a target is mostly UI and lifecycle code, this mode is a serious option rather than an edge case.

**Important:** Some users believe that making their app target `@MainActor` means that networking will also run on the main actor, which is not true – that’s an external module, so it runs elsewhere like it always has.


## Global-actor isolated conformances

Swift 6.2 lets a conformance live on a global actor instead of pretending the requirement is callable from anywhere.

```swift
@MainActor
class User: @MainActor Equatable {
    var id: UUID
    var name: String

    init(name: String) {
        self.id = UUID()
        self.name = name
    }

    static func ==(lhs: User, rhs: User) -> Bool {
        lhs.id == rhs.id
    }
}
```

Review implications:

- A `@MainActor` type can satisfy a protocol while keeping the conformance actor-bound.
- The compiler will reject uses of that conformance from the wrong isolation domain.
- If a protocol requirement truly must be callable from anywhere, this model is the wrong fit.


## Run `nonisolated` async functions on the caller's actor by default

Swift 6.2 changes the mental model for plain async methods. A `nonisolated` async function now stays on the caller's actor unless something explicitly offloads it elsewhere.

```swift
struct Measurements {
    func fetchLatest() async throws -> [Double] {
        let url = URL(string: "https://hws.dev/readings.json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([Double].self, from: data)
    }
}

@MainActor
struct WeatherStation {
    let measurements = Measurements()

    func getAverageTemperature() async throws -> Double {
        let readings = try await measurements.fetchLatest()
        return readings.reduce(0, +) / Double(readings.count)
    }
}
```

Before Swift 6.2, the call to `measurements.fetchLatest()` would leave the caller's actor automatically. In Swift 6.2 and later, it stays on the caller's actor unless you say otherwise.

Review implications:

- Plain async on an owned helper no longer implies background execution.
- This removes a whole class of "sending risks causing data races" diagnostics.
- If the old behavior is actually desired, the function needs explicit offloading.


## Offloading work with `@concurrent`

`@concurrent` is the opt-in tool for code that should leave the caller's actor and run on the concurrent pool.

```swift
nonisolated struct Measurements {
    @concurrent
    func analyzeReadings(_ readings: [Double]) async -> AnalysisResult { ... }
}

let result = await Measurements().analyzeReadings(readings)
```

Review implications:

- Use this for CPU-heavy work such as parsing, image processing, compression, or large transforms.
- Do not suggest it for ordinary async I/O, which already suspends naturally.
- If a function is `nonisolated` but still expected to run "in the background", check whether `@concurrent` is the missing piece.


## Starting tasks synchronously from caller context

`Task.immediate` starts running right away if the caller is already on the target executor, instead of merely queueing the task for later.

```swift
print("Starting")

Task {
    print("In Task")
}

Task.immediate {
    print("In Immediate Task")
}

print("Done")
try await Task.sleep(for: .seconds(0.1))
```

That ordering means `Task.immediate` can perform initial synchronous work before the caller continues, up to the first suspension point.

Review implications:

- Use it only when that immediate start is the point.
- It is still an unstructured task after that first synchronous stretch.
- Task groups also gained `addImmediateTask()` and `addImmediateTaskUnlessCancelled()` for the same immediate-start behavior with child tasks.


## Isolated deinit

By default, a deinitializer on an actor-isolated class is *not* isolated - it runs outside the actor, even if the class itself is `@MainActor`. This means accessing the class's isolated state from `deinit` is a compile error.

Mark the deinitializer `isolated` to run it on the class's actor:

```swift
@MainActor
class Session {
    let user: User

    init(user: User) {
        self.user = user
        user.isLoggedIn = true
    }

    isolated deinit {
        // Runs on the main actor, so accessing user is safe.
        user.isLoggedIn = false
    }
}
```

Without `isolated`, the deinit would fail to compile because `user` is main actor-isolated and the deinitializer is not. Use this whenever teardown logic needs to touch actor-protected state.


## Task priority escalation APIs

Swift 6.2 exposes priority escalation directly. Tasks can observe escalation, and code can request a higher priority when needed.

```swift
let newsFetcher = Task(priority: .medium) {
    try await withTaskPriorityEscalationHandler {
        let url = URL(string: "https://hws.dev/messages.json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    } onPriorityEscalated: { oldPriority, newPriority in
        print("Priority has been escalated to \(newPriority)")
    }
}

newsFetcher.escalatePriority(to: .high)
```

Review implications:

- Priority escalation is usually automatic when a higher-priority task waits on lower-priority work.
- Manual escalation exists, but most code should leave this to the runtime.
- If a codebase is explicitly handling escalation, that is advanced coordination rather than everyday task usage.


## Task naming

Swift 6.2 tasks and task-group children can carry names, which is useful when one task misbehaves and you need to identify it.

```swift
let task = Task(name: "MyTask") {
    print("Current task name: \(Task.name ?? "Unknown")")
}
```

Task groups support naming too:

```swift
let stories = await withTaskGroup { group in
    for i in 1...5 {
        group.addTask(name: "Stories \(i)") {
            do {
                let url = URL(string: "https://hws.dev/news-\(i).json")!
                let (data, _) = try await URLSession.shared.data(from: url)
                return try JSONDecoder().decode([NewsStory].self, from: data)
            } catch {
                print("Loading \(Task.name ?? "Unknown") failed.")
                return []
            }
        }
    }

    var allStories = [NewsStory]()

    for await stories in group {
        allStories.append(contentsOf: stories)
    }

    return allStories
}
```

Review implications:

- Task names are debugging aids, not correctness features.
- They are worth keeping when logs, tracing, or failure diagnosis matter.
