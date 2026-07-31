# OnlySwitch Agent Guidance

This file defines the default workflow for changes to the OnlySwitch project. It applies to the macOS app, widgets, remote app, Swift Package modules, tests, OpenClaw integration, and project documentation.

## Workflow

For every task, follow these steps in order. Each phase is delegated to the named subagent/model, and its output is handed to the next phase:

1. **Identify the task — subagent: 5.6 Luna.** Restate the requested outcome, inspect the relevant project files, and analyze the primary use cases, failure modes, and edge cases. Include impacts on macOS permissions, menu-bar behavior, widgets, remote control, persistence, localization, accessibility, and security when relevant.
2. **Write the implementation plan — subagent: 5.6 Terra.** Ask the user whether they want an implementation plan written first. When accepted, load the `writing-plans` skill, save the completed plan under `doc/plan/`, and use it as the source of truth while implementing. For small, self-contained changes, the user may choose to proceed without a saved plan.
3. **Load relevant skills using Context Routing — subagent: 5.6 Luna.** Select only the skills whose routing conditions match the task. Do not load every skill or every skill markdown by default. See [Context Routing](#context-routing).
4. **Summarize constraints — subagent: 5.6 Luna.** Before changing files, briefly summarize applicable architecture rules, platform/deployment constraints, compatibility requirements, existing conventions, and any assumptions.
5. **Implement unit tests — subagent: 5.6 Terra.** Ask whether the user wants test-driven development for the task. If yes, write or update tests before production code where practical. If no, still add or update focused regression tests when the risk warrants them. Skip this phase only when tests are not meaningful for the requested change.
6. **Implement the feature — subagent: 5.6 sol.** Make the smallest coherent change that satisfies the task, following the applicable Context Routing guidance and the saved plan when one exists.
7. **Review the code — subagent: 5.6 Terra.** Review the implementation and tests for correctness, architecture compliance, edge cases, concurrency safety, permissions/privacy risks, and regressions. Apply or request fixes before reporting completion. Run the narrowest relevant checks, then broader checks when appropriate, and report what changed, what was verified, and any known limitations.

When a task is explicitly urgent or the user has already answered one of the workflow questions in the current conversation, do not ask the same question again; carry that decision forward for the task.

## Context Routing

Skills are opt-in by task context. First inspect the task and repository; then load only the matching skill instructions. A skill is not loaded merely because it is available.

| Context or trigger | Load skill guidance when | Do not load when |
| --- | --- | --- |
| `swiftui-pro` (`doc/skills/swiftui-pro/SKILL.md`) | Reviewing, designing, or implementing SwiftUI views, view state, navigation, accessibility, animations, or SwiftUI performance | The task does not inspect or change SwiftUI code |
| `swift-concurrency-pro` (`doc/skills/swift-concurrency-pro/SKILL.md`) | Reviewing, designing, or implementing Swift concurrency, actors, `Sendable`, isolation, async streams, cancellation, or strict-concurrency fixes | The task does not inspect or change concurrency code |
| `swift-testing-pro` (`doc/skills/swift-testing-pro/SKILL.md`) | Writing, migrating, reviewing, or improving Swift Testing/XCTest code or test strategy | No test code or test strategy is in scope |
| `app-store-review` (`doc/skills/app-store-review/SKILL.md`) | Reviewing macOS app code for App Store Review Guidelines, submission readiness, safety, privacy, legal, design, business, or performance risks | The task is not related to App Store compliance or release readiness |
| `writing-plans` (`doc/skills/writing-plans/SKILL.md`) | The user requests a multi-step implementation plan, or the workflow's plan step is accepted | The user declines a plan or the task is small and self-contained |

Use the narrowest applicable skill. If several conditions match, load the smallest set that covers the work and state the selection in the task update. Skill instructions may route to more specific references; follow only those references needed for the current task. For the project-local `writing-plans` skill, always save plans as `doc/plan/YYYY-MM-DD-<feature-name>.md`; this project location overrides any generic default path in the skill.

## Project-specific working rules

- Treat `ARCHITECTURE.md` as the source of truth for architectural constraints.
- Keep implementation plans in `doc/plan/`. Keep reusable skill notes, routing supplements, and project-specific skill instructions in `doc/skills/`.
- Keep business logic out of SwiftUI views. Move state transitions, validation, orchestration, and side effects into TCA reducers, domain types, or injected clients.
- Preserve the boundaries between the macOS app, widget extension, remote app, and reusable Swift Package modules.
- Prefer focused, composable modules and reusable abstractions over expanding monolithic files.
- Maintain Swift 6 concurrency safety, including explicit sendability and actor isolation at networking, persistence, and process-boundary crossings.
- Treat shell commands, Apple Events, keychain access, system settings, and user permissions as security-sensitive effects that require explicit dependencies and testable failure handling.
- Avoid unrelated formatting or refactoring. Update documentation when a change alters an architectural decision or workflow.

