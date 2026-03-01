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
    /// Nanosecond-resolution point in time.
    ///
    /// Base storage type for hardware clocks (Continuous, Suspending).
    /// Stores nanoseconds since boot as a `UInt64`. Arithmetic wraps on overflow,
    /// matching kernel clock behavior.
    ///
    /// Not used directly — clock instant types are `Tagged<ClockType, Clock.Nanoseconds>`.
    public struct Nanoseconds: InstantProtocol, Sendable, Hashable, Comparable {
        public typealias Duration = Swift.Duration

        /// Nanoseconds since boot.
        public let rawValue: UInt64

        @inlinable
        public init(_ rawValue: UInt64) { self.rawValue = rawValue }

        @inlinable
        public func advanced(by duration: Swift.Duration) -> Self {
            let (seconds, attoseconds) = duration.components
            let nanos = seconds * 1_000_000_000 + attoseconds / 1_000_000_000
            return Self(rawValue &+ UInt64(bitPattern: nanos))
        }

        @inlinable
        public func duration(to other: Self) -> Swift.Duration {
            let diff = Int64(bitPattern: other.rawValue &- rawValue)
            return .nanoseconds(diff)
        }

        @inlinable
        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}
