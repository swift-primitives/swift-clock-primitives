// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-clock-primitives open source project
//
// Copyright (c) 2025 Coen ten Thije Boonkkamp and the swift-clock-primitives project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

extension Clock.Continuous {
    /// A point in continuous-clock time for deadline-based scheduling.
    ///
    /// A deadline is an absolute instant on the continuous monotonic clock
    /// (`Clock.Continuous`). Storing the deadline under
    /// `Clock.Continuous` makes the clock identity explicit in the
    /// type path: mixing a continuous-clock deadline with a suspending-clock
    /// instant is a compile error.
    ///
    /// ## Usage
    /// ```swift
    /// let now = Clock.Continuous.now  // platform-provided
    ///
    /// // Create a deadline 100 ms in the future.
    /// let deadline = Clock.Continuous.Deadline.after(.milliseconds(100), from: now)
    ///
    /// // Check expiry against a later instant.
    /// let later = Clock.Continuous.now
    /// if deadline.hasExpired(at: later) {
    ///     // deadline expired
    /// }
    ///
    /// // Infinite timeout sentinel.
    /// let noTimeout = Clock.Continuous.Deadline.never
    /// ```
    public struct Deadline: Sendable, Hashable {
        /// The absolute instant at which this deadline expires.
        public let instant: Clock.Continuous.Instant

        /// Creates a deadline at the given instant.
        @inlinable
        public init(_ instant: Clock.Continuous.Instant) {
            self.instant = instant
        }

        /// A deadline that never expires.
        ///
        /// Use this for operations that should wait indefinitely.
        @inlinable
        public static var never: Deadline {
            Deadline(Clock.Continuous.Instant(nanoseconds: .max))
        }

        /// Creates a deadline at the given reference instant.
        ///
        /// - Parameter instant: The instant at which the deadline expires.
        @inlinable
        public static func now(at instant: Clock.Continuous.Instant) -> Deadline {
            Deadline(instant)
        }

        /// Creates a deadline at the specified duration past the given instant.
        ///
        /// Uses saturating arithmetic: offsets that would overflow to the
        /// far future clamp to `.never`; offsets that would underflow past
        /// zero clamp to instant zero.
        ///
        /// - Parameters:
        ///   - duration: Offset from the reference instant. Negative
        ///     durations create a deadline in the past (already expired).
        ///   - instant: The reference instant.
        @inlinable
        public static func after(
            _ duration: Duration,
            from instant: Clock.Continuous.Instant
        ) -> Deadline {
            let currentNs = instant.nanoseconds
            let (seconds, attoseconds) = duration.components
            let (secNanos, overflowMul) = seconds.multipliedReportingOverflow(by: 1_000_000_000)
            if overflowMul {
                return seconds > 0 ? .never : Deadline(Clock.Continuous.Instant(nanoseconds: 0))
            }
            let totalNanos = secNanos &+ (attoseconds / 1_000_000_000)
            if totalNanos >= 0 {
                let added = currentNs &+ UInt64(totalNanos)
                return Deadline(
                    Clock.Continuous.Instant(nanoseconds: added < currentNs ? .max : added)
                )
            } else {
                let absNs = UInt64(-totalNanos)
                let subtracted = currentNs &- absNs
                return Deadline(
                    Clock.Continuous.Instant(nanoseconds: subtracted > currentNs ? 0 : subtracted)
                )
            }
        }
    }
}

// MARK: - Comparable

extension Clock.Continuous.Deadline: Comparable {
    @inlinable
    public static func < (lhs: Clock.Continuous.Deadline, rhs: Clock.Continuous.Deadline) -> Bool {
        lhs.instant < rhs.instant
    }
}

// MARK: - Queries

extension Clock.Continuous.Deadline {
    /// Whether this deadline has expired relative to the given instant.
    ///
    /// - Parameter instant: The instant to test against.
    @inlinable
    public func hasExpired(at instant: Clock.Continuous.Instant) -> Bool {
        instant >= self.instant
    }

    /// Time remaining until this deadline.
    ///
    /// Returns `.zero` if the deadline has already expired.
    ///
    /// - Parameter instant: The instant to measure from.
    @inlinable
    public func remaining(at instant: Clock.Continuous.Instant) -> Duration {
        self.instant > instant ? instant.duration(to: self.instant) : .zero
    }
}
