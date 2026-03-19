# Clock / Kernel.Time Unification

| Field | Value |
|-------|-------|
| **Date** | 2026-03-19 |
| **Status** | DECISION |
| **Tier** | 2 (cross-package design decision) |
| **Trigger** | `CLOCK_MONOTONIC` vs `CLOCK_MONOTONIC_RAW` mismatch caused 5.5-second deadline bug in swift-io |

## Context

Two parallel "monotonic nanoseconds" APIs exist with different underlying clocks:

| API | Darwin | Linux | Windows | Defined At |
|-----|--------|-------|---------|------------|
| `Kernel.Clock.Continuous.now()` | `CLOCK_MONOTONIC_RAW` | `CLOCK_BOOTTIME` | `QueryPerformanceCounter` | L2 (iso-9945, windows-primitives) |
| `Kernel.Time.monotonicNanoseconds()` | `CLOCK_MONOTONIC` | `CLOCK_MONOTONIC` | N/A (not implemented) | L2 (iso-9945) |

Deadlines created with one and evaluated with the other drift apart. On the development machine, NTP frequency discipline caused ~5.5 seconds of drift. The swift-io poll paths have already been migrated to `Kernel.Clock.Continuous.now()`.

## Q1: Should `Kernel.Time.monotonicNanoseconds()` be removed?

### Analysis

`CLOCK_MONOTONIC` on Darwin is NTP-frequency-disciplined. It can drift relative to `CLOCK_MONOTONIC_RAW` and, in rare cases, violate strict monotonicity on system time changes. The Swift stdlib and Rust both chose `CLOCK_MONOTONIC_RAW` for exactly this reason.

On Linux, `CLOCK_MONOTONIC` pauses during sleep — it is the *suspending* clock, not the continuous clock. `Kernel.Time.monotonicNanoseconds()` uses `CLOCK_MONOTONIC` on both platforms, which means:

- **Darwin**: Wrong clock (NTP-disciplined, not hardware)
- **Linux**: Suspending clock mislabeled as "monotonic" — callers expecting continuous behavior get suspending behavior

There is no valid use case for `CLOCK_MONOTONIC` specifically. Any caller wanting elapsed-time measurement should use either:
- `Kernel.Clock.Continuous.now()` — advances during sleep, immune to NTP (CLOCK_MONOTONIC_RAW / CLOCK_BOOTTIME)
- `Kernel.Clock.Suspending.now()` — pauses during sleep (CLOCK_UPTIME_RAW / CLOCK_MONOTONIC)

These two typed APIs cover all monotonic time needs with correct, documented semantics.

### Remaining consumers

| Consumer | Location | Migration |
|----------|----------|-----------|
| Windows glob test | `swift-windows/Tests/Windows Kernel Tests/Windows.Kernel.Glob Tests.swift:117` | Replace with `Kernel.Clock.Continuous.now()` — used only for unique directory name generation |
| IO Completions fake driver | `swift-io/Tests/IO Completions Tests/IO.Completion.Driver.Fake.swift:149` | **Private reimplementation** — does not call the ISO 9945 function. Uses `CLOCK_UPTIME_RAW` on Darwin (suspending clock). Should be renamed to `suspendingNanoseconds()` for clarity, but no functional change needed. |

### Decision

**Delete `Kernel.Time.monotonicNanoseconds()`** from iso-9945. Only 1 real consumer remains (glob test), trivially migrated. The API is a trap: its name implies it returns "the" monotonic time, but it returns the wrong clock on Darwin and the wrong semantic (suspending) on Linux.

The fake driver's private reimplementation is not affected — it's a separate function that happens to share the name.

## Q2: Should `Kernel.Time.realtimeEpochSeconds()` be removed or relocated?

### Analysis

Wall-clock time is a legitimate concern, distinct from monotonic time. The question is where it should live.

Current state: `Kernel.Time.realtimeEpochSeconds()` is defined in iso-9945, returns `Double` from `gettimeofday()`. Single consumer: test performance timestamp infrastructure (`swift-tests/Sources/Tests Performance/Test.Trait.Scope.Provider.timed.swift:202`).

Options:
1. **Delete it** — only 1 consumer, in test infrastructure
2. **Move to `Kernel.Clock.Realtime`** — new clock namespace, parallel to Continuous/Suspending
3. **Keep in `Kernel.Time`** — separate concern from monotonic clocks

Option 2 (new `Kernel.Clock.Realtime` namespace) is tempting but premature. Realtime/wall-clock is fundamentally different from monotonic clocks: it can jump backwards, is subject to NTP step adjustments, and should never be used for elapsed-time measurement. Placing it alongside `Continuous` and `Suspending` in `Kernel.Clock` could invite misuse by association.

Option 3 keeps the status quo but perpetuates the confusion between `Kernel.Time` (file timestamps) and `Kernel.Time.realtimeEpochSeconds()` (wall-clock time). `Kernel.Time` is a typealias to `Instant` (seconds + nanoseconds since Unix epoch) — it *is* wall-clock time for file timestamps. Adding `realtimeEpochSeconds()` as a static method on this typealias is actually coherent: both represent wall-clock time, just in different formats.

### Decision

**Keep `Kernel.Time.realtimeEpochSeconds()` where it is.** The single consumer is in test infrastructure (performance timestamps), which is a valid use of wall-clock time. The API is correctly named, correctly documented ("NOT suitable for elapsed time measurement"), and coherently placed on `Kernel.Time` which already represents wall-clock time via its `Instant` typealias.

No action needed. If additional wall-clock APIs are needed in the future, they naturally belong on `Kernel.Time` as well.

## Q3: Should `Kernel.Clock.*` and `Clock.*` be unified?

### Analysis

Two parallel clock namespaces exist for structural reasons:

| Namespace | Layer | Type | Returns | Purpose |
|-----------|-------|------|---------|---------|
| `Kernel.Clock.{Continuous,Suspending}` | L1 enum (kernel-primitives), L2 impl (iso-9945, windows) | Empty enum | `UInt64` nanoseconds | Raw syscall wrapper for kernel/IO code |
| `Clock.{Continuous,Suspending}` | L1 struct (clock-primitives), L2 `_Concurrency.Clock` conformance | Struct | `Tagged<_, Clock.Nanoseconds>` (typed `Instant`) | Application-level typed clock |

The relationship is already clean: `Clock.Continuous.now` delegates to `Kernel.Clock.Continuous.now()` and wraps the result in a typed `Instant`:

```swift
// In iso-9945 (L2):
extension Clock.Continuous: _Concurrency.Clock {
    public var now: Instant {
        Instant(nanoseconds: Kernel.Clock.Continuous.now())
    }
}
```

#### Option 1: Status quo — Two namespaces coexist

**Pros**: Clean separation of concerns. `Kernel.Clock.*` is the raw syscall for IO/kernel code that needs `UInt64`. `Clock.*` is the typed API for application code.

**Cons**: Two "now" functions that return the same underlying value in different types. Discoverability cost.

#### Option 2: Merge into `Clock` — `Clock.Continuous.now() -> UInt64` at L1

**Rejected**. Violates L1 constraints — clock implementations require platform modules. Also pollutes the typed `Clock` namespace with raw `UInt64` APIs.

#### Option 3: Merge into `Kernel.Clock` — Make `Kernel.Clock.Continuous` the canonical source

**Rejected**. `Kernel.Clock.Continuous` is an empty enum at L1 — it cannot hold the struct fields needed for `_Concurrency.Clock` conformance. Would require restructuring both packages.

#### Option 4: Bridge — typed accessor on `Kernel.Clock.Continuous`

**Rejected**. Requires cross-package dependency from kernel-primitives to clock-primitives, creating a lateral dependency at L1.

### Decision

**Status quo (Option 1).** The two-namespace design is intentional and structurally sound:

- `Kernel.Clock.Continuous.now() -> UInt64` — for code that operates at the syscall boundary (IO event loops, deadline arithmetic with raw nanoseconds)
- `Clock.Continuous.now -> Clock.Continuous.Instant` — for application code that wants type safety and `_Concurrency.Clock` conformance

The delegation is one-directional (`Clock.*` → `Kernel.Clock.*`), the types are distinct, and the purposes don't overlap. Document the relationship in `Kernel.Clock`'s doc comments.

## Q4: What should happen to `Kernel.Time.Deadline`?

### Analysis

`Kernel.Time.Deadline` takes `monotonicNanoseconds: UInt64` in all its factory/query methods. The doc comments already reference `Kernel.Clock.Continuous.now()` as the intended source. The parameter name `monotonicNanoseconds` is technically correct but misleading — it doesn't distinguish *which* monotonic clock, and on Linux `CLOCK_MONOTONIC` is the suspending clock, not the continuous one.

#### Q4a: Rename parameter to `continuousNanoseconds`?

**Breaking change** for all call sites. But the parameter name `monotonicNanoseconds` is the root cause of the confusion that led to the 5.5-second bug — callers see "monotonic" and reach for `Kernel.Time.monotonicNanoseconds()`, not `Kernel.Clock.Continuous.now()`.

After deleting `Kernel.Time.monotonicNanoseconds()` (Q1), the misleading name is still a documentation smell, but there's no longer a wrong API to accidentally reach for. The parameter could be renamed, but the benefit is marginal against the migration cost.

#### Q4b: Move to `Clock.Continuous.Deadline`?

**Rejected.** `Kernel.Time.Deadline` lives at L1 (kernel-primitives) and is used by IO code that operates on raw `UInt64`. Moving it to `Clock.Continuous` would require either:
- Making it depend on clock-primitives (lateral L1 dependency), or
- Placing it at L2 where IO code can't reach it without pulling in Clock

The current placement is correct: deadline is a kernel-level concept that takes raw nanoseconds.

#### Q4c: Factory method taking `Clock.Continuous.Instant`?

This would require clock-primitives to depend on kernel-primitives (for the `Deadline` type) or vice versa. Neither direction is clean. Better to add this as an extension in a package that imports both — iso-9945 or a consumer package.

### Decision

**Keep `Kernel.Time.Deadline` where it is, with current parameter names.** After removing `Kernel.Time.monotonicNanoseconds()`, the trap is eliminated. The doc comments already direct callers to `Kernel.Clock.Continuous.now()`. Rename is not worth the breaking change.

**Optional enhancement**: Add a convenience extension in iso-9945 (L2) that bridges `Clock.Continuous.Instant` to `Kernel.Time.Deadline`:

```swift
extension Kernel.Time.Deadline {
    public static func now(at instant: Clock.Continuous.Instant) -> Deadline {
        Deadline(nanoseconds: instant.nanoseconds)
    }

    public func hasExpired(at instant: Clock.Continuous.Instant) -> Bool {
        hasExpired(at: instant.nanoseconds)
    }
}
```

This is additive, non-breaking, and lives at L2 where both types are available. **Deferred** — implement when a consumer needs it.

## Q5: What is the `Kernel.Time` typealias for?

### Analysis

`Kernel.Time = Instant` where `Instant` is from time-primitives (seconds + nanosecond fraction since Unix epoch). Used for:

- File timestamps: `Kernel.File.Stats.{accessTime, modificationTime, changeTime}: Kernel.Time`
- Static utilities: `Kernel.Time.milliseconds(from:)` (Duration → CInt for epoll/poll)
- Monotonic/realtime accessors added at L2 (the problematic `monotonicNanoseconds()` and the fine `realtimeEpochSeconds()`)

The confusion arises because `Kernel.Time` does double duty:
1. **Calendar time** — file timestamps (its primary purpose via `Instant`)
2. **Clock operations** — monotonic/realtime static methods bolted on at L2

After removing `monotonicNanoseconds()` (Q1), the only remaining L2 method is `realtimeEpochSeconds()`, which is coherent with the calendar-time purpose. The `milliseconds(from:)` utility is a pure conversion function for Duration, not a clock operation.

### Decision

**Keep `Kernel.Time` as-is.** After removing `monotonicNanoseconds()`, the remaining surface is coherent:

- `Kernel.Time` (typealias) → file timestamps, calendar time
- `Kernel.Time.Deadline` → monotonic deadline (takes raw `UInt64`, clock-agnostic)
- `Kernel.Time.Deadline.Next` → atomic deadline storage
- `Kernel.Time.milliseconds(from:)` → pure Duration conversion
- `Kernel.Time.realtimeEpochSeconds()` → wall-clock time (coherent with calendar-time purpose)

No rename needed. The monotonic clock operations are properly in `Kernel.Clock.*`.

## Q6: Platform completeness

### Darwin

| Clock | API | Status |
|-------|-----|--------|
| Continuous | `clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)` | Correct |
| Suspending | `clock_gettime_nsec_np(CLOCK_UPTIME_RAW)` | Correct |

No mismatch risk after removing `monotonicNanoseconds()`.

### Linux (Glibc + Musl)

| Clock | API | Status |
|-------|-----|--------|
| Continuous | `clock_gettime(CLOCK_BOOTTIME)` | Correct |
| Suspending | `clock_gettime(CLOCK_MONOTONIC)` | Correct |

No mismatch risk. `CLOCK_BOOTTIME` advances during sleep; `CLOCK_MONOTONIC` pauses.

### Windows

| Clock | API | Status |
|-------|-----|--------|
| Continuous | `QueryPerformanceCounter` | Correct |
| Suspending | `QueryUnbiasedInterruptTime` | Correct |

No `monotonicNanoseconds()` implementation exists on Windows — no mismatch risk. `QueryPerformanceCounter` is the hardware timer (always advances, immune to NTP). `QueryUnbiasedInterruptTime` subtracts sleep time.

**Note**: `QueryPerformanceCounter` calls `QueryPerformanceFrequency` on every invocation. This is safe (the frequency is constant and cached by the kernel) but could be optimized by caching the frequency value. Not a correctness issue — deferred.

### WASI / OpenBSD / Embedded

No dedicated clock primitives exist for these platforms. The `#if` guards in kernel-primitives include `os(OpenBSD)` but no implementation exists in iso-9945 (which doesn't compile for OpenBSD). No WASI or embedded implementations exist.

**Assessment**: Not a gap that needs filling now. These platforms can be added when there's a consumer. The architecture supports it — add a new L2 package (e.g., `swift-wasi-primitives`) with extensions on `Kernel.Clock.Continuous` and `Kernel.Clock.Suspending`.

### Fake driver note

The IO completions fake driver (`IO.Completion.Driver.Fake.swift:149`) has a private `monotonicNanoseconds()` that uses `CLOCK_UPTIME_RAW` on Darwin — this is actually the **suspending** clock, not the continuous clock. The name is misleading but the behavior is correct for its use case (deadline expiration in tests where sleep behavior doesn't matter). Consider renaming to `suspendingNanoseconds()` for clarity, but this is cosmetic.

## Migration Plan

### Phase 1: Delete `Kernel.Time.monotonicNanoseconds()` (iso-9945)

1. **Migrate glob test** (`swift-windows/Tests/Windows Kernel Tests/Windows.Kernel.Glob Tests.swift:117`):
   - Replace `Kernel.Time.monotonicNanoseconds()` with `Kernel.Clock.Continuous.now()`
   - This is for unique name generation — any monotonic source works

2. **Delete** `monotonicNanoseconds()` from `/Users/coen/Developer/swift-iso/swift-iso-9945/Sources/ISO 9945 Kernel/ISO 9945.Kernel.Time.swift:54-64`

3. **Verify** no other consumers exist (grep confirmed: only the glob test and the private fake driver reimplementation)

### Phase 2: Documentation (optional)

1. Add cross-reference doc comment on `Kernel.Clock` pointing to `Clock.*` for typed instants
2. Consider renaming fake driver's `monotonicNanoseconds()` to `suspendingNanoseconds()`

### Phase 3: Convenience bridge (deferred)

Add `Kernel.Time.Deadline` extension in iso-9945 accepting `Clock.Continuous.Instant` — implement when a consumer needs it.

## Decision Summary

| Question | Decision | Action |
|----------|----------|--------|
| Q1: Remove `monotonicNanoseconds()`? | **Yes, delete** | Migrate 1 consumer, delete function |
| Q2: Remove/relocate `realtimeEpochSeconds()`? | **Keep as-is** | No action |
| Q3: Unify `Kernel.Clock.*` and `Clock.*`? | **Status quo** | Two namespaces coexist by design |
| Q4: Rename/move `Kernel.Time.Deadline`? | **Keep as-is** | Optional bridge deferred |
| Q5: Rename `Kernel.Time`? | **Keep as-is** | Coherent after Q1 removal |
| Q6: Platform completeness? | **Complete for supported platforms** | WASI/OpenBSD deferred |

## Cross-References

| Package | Affected Files |
|---------|---------------|
| swift-iso-9945 | `Sources/ISO 9945 Kernel/ISO 9945.Kernel.Time.swift` (delete `monotonicNanoseconds()`) |
| swift-iso-9945 | `Sources/ISO 9945 Kernel/ISO 9945.Kernel.Clock.swift` (no changes — canonical implementation) |
| swift-windows (in swift-foundations) | `Tests/Windows Kernel Tests/Windows.Kernel.Glob Tests.swift:117` (migrate consumer) |
| swift-io (in swift-foundations) | `Tests/IO Completions Tests/IO.Completion.Driver.Fake.swift:149` (cosmetic rename, optional) |
| swift-tests (in swift-foundations) | `Sources/Tests Performance/Test.Trait.Scope.Provider.timed.swift:202` (no changes — uses `realtimeEpochSeconds()`) |
| swift-kernel-primitives | `Sources/Kernel Time Primitives/Kernel.Time.Deadline.swift` (no changes) |
| swift-clock-primitives | `Sources/Clock Primitives/Clock.Continuous.swift` (no changes) |
