# Clock Primitives

![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)

Clock types for Swift — phantom-tagged instants, saturating deadlines, and the standard clock family (continuous, suspending, test, immediate, unimplemented), with zero platform dependencies.

---

## Quick Start

`Clock` is the namespace for time measurement and scheduling. Instants are phantom-tagged so a continuous-clock instant and a suspending-clock instant are distinct types that cannot be mixed at compile time — the storage is identical (`UInt64` nanoseconds), but the tag keeps the clock identity in the type.

```swift
import Clock_Primitives

// Instants carry their clock's identity in the type.
let start = Clock.Continuous.Instant(nanoseconds: 1_000_000_000)
let later = start.advanced(by: .seconds(2))

let elapsed: Duration = start.duration(to: later)   // .seconds(2)
print(later.nanoseconds)                            // 3_000_000_000

// Mixing clocks is a compile error, not a runtime bug:
// let bad = start.duration(to: Clock.Suspending.Instant(nanoseconds: 0))  // ✗ won't compile
```

Deadlines are absolute instants on the continuous monotonic clock. Construction uses saturating arithmetic — offsets that would overflow clamp to `.never` rather than wrapping:

```swift
let deadline = Clock.Continuous.Deadline.after(.milliseconds(100), from: start)

if deadline.hasExpired(at: later) {
    // `later` is at or past the deadline
}

let noTimeout = Clock.Continuous.Deadline.never   // infinite-timeout sentinel
```

For tests, `Clock.Test` advances only when you tell it to, so time-dependent code runs deterministically with no real delays:

```swift
let clock = Clock.Test()
clock.advance(by: .seconds(5))
print(clock.now.offset)                 // .seconds(5)

// `sleep` suspends until the clock is advanced past the deadline.
try await clock.sleep(until: .init(offset: .seconds(1)))   // already passed → returns at once
```

The clock family also includes `Clock.Suspending` (pauses while the system sleeps), `Clock.Immediate` (squashes all sleeps to an instant, for previews), `Clock.Unimplemented` (traps if any endpoint is touched, to prove a path is time-free), and `Clock.Any<Duration>` (type erasure over any `Clock` sharing a duration type).

---

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/swift-primitives/swift-clock-primitives.git", branch: "main")
]
```

```swift
.target(
    name: "App",
    dependencies: [
        .product(name: "Clock Primitives", package: "swift-clock-primitives"),
    ]
)
```

Requires Swift 6.3.1 and macOS 26 / iOS 26 / tvOS 26 / watchOS 26 / visionOS 26 (or the matching Linux / Windows toolchain).

---

## Architecture

Two library products.

| Product | Target | Purpose |
|---------|--------|---------|
| `Clock Primitives` | `Sources/Clock Primitives/` | The `Clock` namespace: `Clock.Nanoseconds` / `Clock.Offset` instant storage, phantom-tagged `Continuous` / `Suspending` / `Test` / `Immediate` / `Unimplemented` clocks, `Clock.Continuous.Deadline` (+ atomic `Deadline.Next`), and `Clock.Any` type erasure. |
| `Clock Primitives Test Support` | `Tests/Support/` | Re-exports the main target for test consumers. |

Foundation-free. Builds on `swift-tagged-primitives` (phantom typing), `swift-carrier-primitives` (cross-clock generic dispatch), and `swift-standard-library-extensions`.

---

## Platform Support

| Platform | Status |
|----------|--------|
| macOS 26 | Full support |
| Linux | Full support |
| Windows | Full support |
| iOS / tvOS / watchOS / visionOS | Supported |
| Swift Embedded | Partial (time types; async sleep excluded) |

Under Embedded Swift the non-async time surface — instants, deadlines, duration arithmetic, and the `Continuous` / `Suspending` clock value types — is available. The clocks whose `async` `sleep` is defined in this package (`Test`, `Immediate`, `Unimplemented`, `Any`) are excluded under Embedded because it has no `_Concurrency` module.

---

## Community

<!-- BEGIN: discussion -->
<!-- Discussion thread created at publication. -->
<!-- END: discussion -->

## License

Apache 2.0. See [LICENSE.md](LICENSE.md).
