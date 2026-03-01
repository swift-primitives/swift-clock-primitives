// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-clock-primitives open source project
//
// Copyright (c) 2025 Coen ten Thije Boonkkamp and the project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

extension Clock {
    /// A clock that measures elapsed time, continuing to advance while the system is asleep.
    ///
    /// Equivalent to Swift stdlib's `ContinuousClock` semantics:
    /// - **Darwin**: Uses `CLOCK_MONOTONIC_RAW` (immune to NTP adjustments)
    /// - **Linux**: Uses `CLOCK_BOOTTIME`
    /// - **Windows**: Uses `QueryPerformanceCounter`
    ///
    /// Use this clock when you need to measure total wall-clock time elapsed,
    /// including periods when the system was asleep.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let clock = Clock.Continuous()
    /// let start = clock.now
    /// // ... perform work (system may sleep) ...
    /// let elapsed: Duration = clock.now - start
    /// ```
    ///
    /// - Note: `_Concurrency.Clock` conformance is added via extension in
    ///   swift-iso-9945 (POSIX) or swift-windows-primitives (Windows).
    public struct Continuous: Sendable {
        public typealias Duration = Swift.Duration

        /// The instant type for continuous clock measurements.
        ///
        /// Phantom-tagged nanosecond position. Type-distinct from `Clock.Suspending.Instant`
        /// by construction — the two cannot be mixed at compile time.
        public typealias Instant = Tagged<Continuous, Clock.Nanoseconds>

        public var minimumResolution: Duration { .nanoseconds(1) }

        /// Creates a continuous clock instance.
        public init() {}

        // Note: `now` property is provided via extension in swift-iso-9945 (POSIX)
        // or swift-windows-primitives (Windows)

        // Note: `sleep(until:tolerance:)` is provided via extension in swift-iso-9945 (POSIX)
        // or swift-windows-primitives (Windows)
    }
}
