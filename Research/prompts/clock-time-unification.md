# Clock / Kernel.Time Unification — Research Prompt

## Trigger

A `CLOCK_MONOTONIC` vs `CLOCK_MONOTONIC_RAW` mismatch caused a 5.5-second deadline bug in swift-io. Deadlines were created with `Kernel.Clock.Continuous.now()` (`CLOCK_MONOTONIC_RAW` on Darwin) but evaluated with `Kernel.Time.monotonicNanoseconds()` (`CLOCK_MONOTONIC`). NTP frequency discipline caused the two clocks to drift apart by ~5.5 seconds on the development machine.

The fix was a two-line change (use the same clock), but the existence of two parallel "monotonic nanoseconds" APIs with different underlying clocks is a design defect. This research investigates whether `Kernel.Time` should exist at all alongside the clock primitives.

## Current State

### Two parallel monotonic-time APIs

| API | Clock Source (Darwin) | Clock Source (Linux) | Defined At |
|-----|----------------------|---------------------|------------|
| `Kernel.Clock.Continuous.now() -> UInt64` | `CLOCK_MONOTONIC_RAW` | `CLOCK_BOOTTIME` | L2 (iso-9945, windows-primitives) |
| `Kernel.Time.monotonicNanoseconds() -> UInt64` | `CLOCK_MONOTONIC` | `CLOCK_MONOTONIC` | L2 (iso-9945) |

On Darwin, `CLOCK_MONOTONIC_RAW` is the hardware timer immune to NTP. `CLOCK_MONOTONIC` is NTP-disciplined and can drift. The Swift stdlib and Rust both chose `CLOCK_MONOTONIC_RAW` for this reason.

On Linux, `CLOCK_BOOTTIME` advances during sleep; `CLOCK_MONOTONIC` pauses. Different behavior, not just drift.

### Two parallel clock namespaces

| Namespace | Layer | Purpose | Types |
|-----------|-------|---------|-------|
| `Clock.{Continuous,Suspending,Test,Immediate,Unimplemented,Any}` | L1 (swift-clock-primitives) | Typed instants with `InstantProtocol`, `_Concurrency.Clock` conformance at L2 | Structs, Tagged typealiases |
| `Kernel.Clock.{Continuous,Suspending}` | L1 namespace (kernel-primitives), L2 impl (iso-9945, windows) | Raw `UInt64` nanoseconds for kernel-level code | Empty enum namespaces with `now() -> UInt64` |
| `Kernel.Time` | L1 type alias (kernel-primitives) | File timestamps (`Instant`-based), deadline types | `Kernel.Time.Deadline`, `Kernel.Time.Deadline.Next` |
| `Kernel.Time.monotonicNanoseconds()` | L2 (iso-9945) | **The problematic API** | Static function returning `UInt64` |
| `Kernel.Time.realtimeEpochSeconds()` | L2 (iso-9945) | Wall-clock time | Static function returning `Double` |

### Kernel.Time.Deadline design

`Kernel.Time.Deadline` stores `nanoseconds: UInt64`. All factory/query methods take `monotonicNanoseconds: UInt64` as an explicit parameter — **no clock source baked in**. Doc comments reference `Kernel.Clock.Continuous.now()` as the intended clock. Lives at L1 (kernel-primitives), so it cannot call `Kernel.Clock.Continuous.now()` directly (that's L2).

### Remaining consumers of `Kernel.Time.monotonicNanoseconds()`

| Consumer | Location | Status |
|----------|----------|--------|
| swift-io poll paths | `IO.Event.{Queue,Poll}.Operations.swift` | **Already migrated** to `Kernel.Clock.Continuous.now()` |
| Windows glob test | `Windows.Kernel.Glob Tests.swift:117` | Single test, trivially migrated |
| IO Completions fake driver | `IO.Completion.Driver.Fake.swift:149` | Private reimplementation (doesn't call the ISO 9945 version) |

### Remaining consumers of `Kernel.Time.realtimeEpochSeconds()`

| Consumer | Location | Notes |
|----------|----------|-------|
| Performance testing | `Test.Trait.Scope.Provider.timed.swift:202` | Single call site in swift-tests |

## Research Questions

### Q1: Should `Kernel.Time.monotonicNanoseconds()` be removed?

It uses `CLOCK_MONOTONIC` which is the wrong clock on Darwin for any deadline or elapsed-time measurement. Every consumer should use `Kernel.Clock.Continuous.now()` or `Kernel.Clock.Suspending.now()` instead.

- Evaluate: is there ANY valid use case for `CLOCK_MONOTONIC` specifically (as opposed to `CLOCK_MONOTONIC_RAW` or `CLOCK_BOOTTIME`)?
- If not, should it be deprecated, or deleted outright? (Only 1 real consumer remains.)

### Q2: Should `Kernel.Time.realtimeEpochSeconds()` be removed or relocated?

Wall-clock time is a distinct concern from monotonic time. Options:
1. Delete it (only 1 consumer, in test infrastructure)
2. Move it to a wall-clock type (`Kernel.Clock.Realtime.now()` or similar)
3. Keep it in `Kernel.Time` as a separate concern

### Q3: Should `Kernel.Clock.*` and `Clock.*` be unified?

Currently there are two parallel clock namespaces:
- `Kernel.Clock.Continuous.now() -> UInt64` (raw nanoseconds, for kernel/IO code)
- `Clock.Continuous` (typed `Instant`, `_Concurrency.Clock` conformance)

The split exists because `Kernel.Clock.Continuous` is defined at L1 (kernel-primitives) as an empty enum, with `now()` added at L2 (iso-9945/windows). `Clock.Continuous` is a struct at L1 (clock-primitives) with `_Concurrency.Clock` conformance added at L2.

Options:
1. **Status quo**: Two namespaces coexist. `Kernel.Clock.*.now()` provides raw UInt64 for low-level code; `Clock.*` provides typed instants for application code. Document the relationship.
2. **Merge into Clock**: Have `Clock.Continuous.now()` return the raw UInt64 at L1, and `Clock.Continuous.Instant.now` return the typed instant. Eliminate `Kernel.Clock.*`.
3. **Merge into Kernel.Clock**: Make `Kernel.Clock.Continuous` the canonical source and have `Clock.Continuous` delegate to it.
4. **Bridge**: Add a typed accessor on `Kernel.Clock.Continuous` that returns `Clock.Continuous.Instant` (requires cross-package dependency).

### Q4: What should happen to `Kernel.Time.Deadline`?

`Kernel.Time.Deadline` takes raw `UInt64` nanoseconds and its parameter name is `monotonicNanoseconds`. Should:
1. The parameter name change to reflect that `Kernel.Clock.Continuous.now()` is the intended source? (e.g., `continuousNanoseconds`)
2. The type move to `Clock.Continuous.Deadline`?
3. The type gain a factory method that takes `Clock.Continuous.Instant` directly?

### Q5: What is the `Kernel.Time` type alias for?

`Kernel.Time` is `typealias Kernel.Time = Instant` (from time-primitives). It's used for file timestamps (`accessTime: Kernel.Time`, `modificationTime: Kernel.Time`). This is a separate concern from monotonic clocks. Should `Kernel.Time` be renamed to something more specific (e.g., `Kernel.FileTime`, `Kernel.Timestamp`) to avoid confusion with the clock operations?

### Q6: Platform completeness

- Does Windows have the same clock mismatch risk? (`QueryPerformanceCounter` vs what?)
- Should all platforms have consistent clock selection?
- Are there embedded/WASI/OpenBSD gaps?

## Constraints

- L1 (primitives) cannot import Foundation or platform modules — clock implementations stay at L2
- `Kernel.Time.Deadline` is at L1 and must remain clock-source-agnostic (takes raw UInt64)
- Any rename of `Kernel.Time.Deadline` parameter names is a breaking API change
- `Clock.Continuous` already conforms to `_Concurrency.Clock` at L2 — any merge must preserve this

## Deliverable

A research document at `/Users/coen/Developer/swift-primitives/swift-clock-primitives/Research/clock-time-unification.md` with:
1. Analysis of each question above
2. Recommended option for each with rationale
3. Migration plan if removals are recommended
4. Cross-references to affected packages

Use `/research-process` skill. Tier 2 (cross-package design decision).
