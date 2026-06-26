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
    /// A clock that measures elapsed time, pausing while the system is asleep.
    ///
    /// Equivalent to Swift stdlib's `SuspendingClock` semantics:
    /// - **Darwin**: Uses `CLOCK_UPTIME_RAW`
    /// - **Linux**: Uses `CLOCK_MONOTONIC`
    /// - **Windows**: Uses `QueryUnbiasedInterruptTime`
    ///
    /// Use this clock for measuring active execution time where system sleep
    /// should not count toward elapsed time.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let clock = Clock.Suspending()
    /// let start = clock.now
    /// // ... perform work ...
    /// let elapsed: Duration = clock.now - start
    /// ```
    ///
    /// - Note: `_Concurrency.Clock` conformance is added via extension in
    ///   swift-iso-9945 (POSIX) or swift-windows-primitives (Windows).
    public struct Suspending: Sendable {
        /// The duration type for suspending-clock measurements.
        public typealias Duration = Swift.Duration

        /// The instant type for suspending clock measurements.
        ///
        /// Phantom-tagged nanosecond position. Type-distinct from `Clock.Continuous.Instant`
        /// by construction.
        public typealias Instant = Tagged<Self, Clock.Nanoseconds>

        /// The smallest measurable duration: one nanosecond.
        public var minimumResolution: Duration { .nanoseconds(1) }

        /// Creates a suspending clock instance.
        public init() {}
    }
}
