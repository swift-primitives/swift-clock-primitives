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
    public struct Suspending: _Concurrency.Clock, Sendable {
        public typealias Duration = Swift.Duration

        /// The instant type for suspending clock measurements.
        public struct Instant: InstantProtocol, Sendable, Hashable {
            /// Nanoseconds since boot (excluding sleep time).
            public let nanoseconds: UInt64

            public init(nanoseconds: UInt64) {
                self.nanoseconds = nanoseconds
            }

            public func advanced(by duration: Duration) -> Self {
                let (seconds, attoseconds) = duration.components
                let nanos = seconds * 1_000_000_000 + attoseconds / 1_000_000_000
                return Instant(nanoseconds: nanoseconds &+ UInt64(nanos))
            }

            public func duration(to other: Self) -> Duration {
                let diff = Int64(bitPattern: other.nanoseconds &- nanoseconds)
                return .nanoseconds(diff)
            }

            public static func < (lhs: Self, rhs: Self) -> Bool {
                lhs.nanoseconds < rhs.nanoseconds
            }
        }

        public var minimumResolution: Duration { .nanoseconds(1) }

        /// Creates a suspending clock instance.
        public init() {}

        /// The current instant according to the suspending clock.
        public var now: Instant {
            Instant(nanoseconds: Kernel.Clock.Suspending.now())
        }

        public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
            let target = deadline.nanoseconds
            while Kernel.Clock.Suspending.now() < target {
                try Task.checkCancellation()
                try await Task.sleep(for: .nanoseconds(1_000_000)) // 1ms granularity
            }
        }
    }
}
