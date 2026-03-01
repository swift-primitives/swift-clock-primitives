# Test Clock Advance Ordering

<!--
---
version: 1.0.0
last_updated: 2026-03-01
status: RECOMMENDATION
tier: 1
---
-->

## Context

The test `advance resumes multiple sleeps in order` in `Clock.Test Tests.swift:172-190`
fails intermittently. Two tasks sleep with different deadlines (2s and 4s), a single
`advance(by: .seconds(5))` resumes both, and the test asserts the post-sleep bodies
execute in deadline order (`[1, 2]`). The observed failure is `[2, 1]`.

This investigation was triggered by the Tagged instant refactor, but the failure is
pre-existing — it's a test design issue, not a regression.

## Question

Why does the ordering assertion fail, and what is the principled fix?

## Analysis

### Mechanism: How `advance(to:)` resumes continuations

```swift
// Clock.Test.swift:114-126
public func advance(to deadline: Instant) {
    let toResume: [CheckedContinuation<Void, Never>] = state.withLock { st in
        st.now = deadline
        st.suspensions.sort { $0.deadline < $1.deadline }
        var ready: [CheckedContinuation<Void, Never>] = []
        while let head = st.suspensions.first, head.deadline <= deadline {
            ready.append(head.continuation)
            st.suspensions.removeFirst()
        }
        return ready
    }
    for c in toResume { c.resume() }  // all resumed in one synchronous loop
}
```

The continuations **are** collected in deadline order (sorted). The `for` loop calls
`c.resume()` in that order. But `CheckedContinuation.resume()` does **not** execute the
continuation body inline — it **enqueues** the task onto the cooperative thread pool.
After the loop, both tasks are enqueued and race for thread pool pickup. The cooperative
thread pool provides **no FIFO guarantee** for enqueued work items.

### `Task.immediate` guarantees registration, not post-resume execution

SE-0472 (`Task.immediate`) guarantees that the task body executes synchronously on the
caller's thread up to its **first real suspension point**. In the test:

```swift
let task1 = Task.immediate {
    try await clock.sleep(until: .init(offset: .seconds(2)))  // suspends here
    order.withLock { $0.append(1) }  // runs AFTER resumption — on thread pool
}
```

`Task.immediate` ensures the sleep **registration** happens before the next line of the
test. But the post-sleep body (`order.append(1)`) runs after the continuation is resumed
by `advance` — at which point it's on the thread pool with no ordering guarantees.

### The real problem: `withCheckedContinuation` is not `nonisolated(nonsending)`

The `sleep` method is `nonisolated(nonsending)`:

```swift
nonisolated(nonsending)
public func sleep(
    until deadline: Instant,
    tolerance: Duration? = nil
) async throws {
    // ...
    await withCheckedContinuation { ... }  // ← stdlib version, NOT nonsending
    // ...
}
```

The method itself inherits the caller's isolation. But `withCheckedContinuation` is the
current stdlib version — it is **not** `nonisolated(nonsending)`. When `resume()` is
called on the continuation, the task is **enqueued** on the cooperative thread pool rather
than executing inline on the caller's thread. This is the source of non-determinism.

If `withCheckedContinuation` were `nonisolated(nonsending)`, then `resume()` would
execute the continuation body **inline on the caller's thread** — making the ordering
in `advance(to:)`'s `for c in toResume` loop fully deterministic.

### Point-Free's diagnosis (Episode 355, "Synchronous sleep")

Point-Free Episode 355 (Feb 23, 2026) identifies this exact problem and its solution:

> "We have now shown that once isolation is strictly controlled that even time-based
> asynchrony can be tested in a synchronous fashion with 100% deterministic results."
> — 29:06

> "And we only showed this for immediate clocks, but a similar thing can be shown with
> test clocks... but there is just a tiny bit of work that needs to be done in Swift
> before this is possible. We need `nonisolated(nonsending)` versions of both
> `withUnsafeContinuation` **and** `withTaskCancellationHandler`. Once that is possible
> test clocks will be able to squash all unnecessary suspension points and give us the
> ability to fully test the flow of time without sprinkling yields all throughout our
> code." — 29:15

They explicitly contrast this with their old `TestClock` approach (async `advance` +
`Task.megaYield`):

> "We were forced to insert little yields into various parts in order to workaround the
> fact that it's nearly impossible to reliably test async code in Swift up until recently."
> — 22:53

> "There isn't a single yield in TCA2 or the ImmediateClock, and that also means that
> large test suites are going to get a lot faster. Those yields were problematic for lots
> of tests running concurrently because it creates a lot of busy work for the scheduler."
> — 28:38

### Point-Free's old approach: `Task.megaYield` (rejected)

Point-Free's current `swift-clocks` 1.x `TestClock.advance(to:)` is `async` and uses
`Task.megaYield()` (20 yields via detached background tasks) between each continuation
resumption. This is a **heuristic workaround** — it's probabilistic, not deterministic,
environment-dependent, and explicitly being replaced by the `nonisolated(nonsending)`
approach in their TCA 2.0 work.

This approach is forbidden at the primitives layer. No `Task.yield()` or `Task.megaYield()`.

### Swift stdlib status: `nonisolated(nonsending)` continuations

A [Swift Forums pre-pitch](https://forums.swift.org/t/pre-pitch-updating-with-checked-unsafe-continuation-to-support-typed-throws-and-perhaps-nonisolated-nonsending/84770)
proposes updating `withCheckedContinuation` and `withUnsafeContinuation` to support both
typed throws and `nonisolated(nonsending)`. Konrad Malawski (ktoso) is actively
implementing these changes. Key points from the thread:

- Multiple pending PRs address `nonisolated(nonsending)` adoption in the Concurrency library
- Changes are "pretty difficult" and have uncovered underlying bugs requiring fixes first
- "ABI must be maintained" — careful overload management required
- Implementation scheduled for "coming weeks" (as of early 2026)
- Typed throws and `nonisolated(nonsending)` will ship together to minimize overloads

Once available, `Clock.Test.sleep` will use the `nonisolated(nonsending)` variant of
`withCheckedContinuation`. At that point, `resume()` will execute the continuation body
inline on the caller's thread, and `advance(to:)`'s `for c in toResume` loop will produce
deterministic execution order.

### Option A: Wait for `nonisolated(nonsending)` continuations

When Swift ships `nonisolated(nonsending)` `withCheckedContinuation`:

1. Update `Clock.Test.sleep` to use the new variant
2. The test becomes deterministic with no code changes
3. The ordering assertion is correct — it tests what `advance` guarantees

**Pros**: Principled. Zero heuristics. Test asserts real behavior.

**Cons**: Blocked on Swift stdlib. Unknown exact timeline (weeks, not months).

### Option B: Sequential advance test pattern (interim)

Rewrite the test to advance to each deadline individually, ensuring only one continuation
is resumed per advance:

```swift
@Test
func `advance resumes multiple sleeps in order`() async throws {
    let clock = Clock.Test()
    let order = OSAllocatedUnfairLock(initialState: [Int]())

    let task1 = Task.immediate {
        try await clock.sleep(until: .init(offset: .seconds(2)))
        order.withLock { $0.append(1) }
    }

    let task2 = Task.immediate {
        try await clock.sleep(until: .init(offset: .seconds(4)))
        order.withLock { $0.append(2) }
    }

    clock.advance(by: .seconds(2))    // resumes only task1
    try await task1.value              // wait for task1 to complete
    clock.advance(by: .seconds(2))    // resumes only task2
    try await task2.value              // wait for task2 to complete
    #expect(order.withLock { $0 } == [1, 2])
}
```

**Pros**: Deterministic now. No API changes. No yields. Tests what is actually
guaranteed today (each sleep wakes at its deadline). Stronger test — verifies tasks
resume at the right time, not just in the right order.

**Cons**: Tests a weaker property than the batch-resume case. Must be revisited when
nonsending continuations arrive (the batch test should be re-enabled).

### Comparison

| Criterion | A: Wait for nonsending | B: Sequential advance |
|-----------|----------------------|-----------------------|
| Determinism | Guaranteed (once available) | Guaranteed (now) |
| Yields | None | None |
| API change | None (sleep impl detail) | None |
| Test strength | Tests batch ordering | Tests per-deadline ordering |
| Available | Blocked on Swift | Now |

## Outcome

**Status**: RECOMMENDATION

1. **Interim (now)**: Apply Option B — rewrite the test to use sequential advances. This
   is deterministic, yield-free, and tests the correct property.

2. **When `nonisolated(nonsending)` `withCheckedContinuation` ships**: Update
   `Clock.Test.sleep` to use the nonsending variant. Re-enable the batch ordering test
   (the original test with a single `advance(by: .seconds(5))`). At that point, the batch
   test will be deterministic because `resume()` will execute inline.

3. **Never**: `Task.yield()`, `Task.megaYield()`, or any heuristic yield pattern.

The test is conceptually correct — `advance(to:)` *does* resume continuations in deadline
order. The non-determinism comes entirely from `withCheckedContinuation` not being
`nonisolated(nonsending)`, which forces a thread hop on resume. This is a Swift stdlib
limitation, not a `Clock.Test` design flaw.

## References

- [SE-0472: Starting tasks synchronously from caller context](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0472-task-start-synchronously-on-caller-context.md)
- [Point-Free Episode 355: Beyond Basics: Isolation, ~Copyable, ~Escapable](https://www.pointfree.co/episodes/ep355-beyond-basics-isolation-copyable-escapable) — "Synchronous sleep" section (22:22–29:15)
- [Pre-Pitch: updating with{Checked|Unsafe}Continuation for typed throws and nonisolated(nonsending)](https://forums.swift.org/t/pre-pitch-updating-with-checked-unsafe-continuation-to-support-typed-throws-and-perhaps-nonisolated-nonsending/84770)
- [Point-Free swift-clocks TestClock](https://github.com/pointfreeco/swift-clocks/blob/main/Sources/Clocks/TestClock.swift) — old `Task.megaYield` approach
- [nonisolated(nonsending) by Default](https://docs.swift.org/compiler/documentation/diagnostics/nonisolated-nonsending-by-default/)
