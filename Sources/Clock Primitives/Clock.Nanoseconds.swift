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
        /// The duration type measuring distance between instants.
        public typealias Duration = Swift.Duration

        /// Nanoseconds since boot.
        public let rawValue: UInt64

        /// Creates an instant from a raw nanosecond count.
        @inlinable
        public init(_ rawValue: UInt64) { self.rawValue = rawValue }

        /// Returns the instant advanced by the given duration, wrapping on overflow.
        @inlinable
        public func advanced(by duration: Swift.Duration) -> Self {
            let (seconds, attoseconds) = duration.components
            let nanos = seconds * 1_000_000_000 + attoseconds / 1_000_000_000
            return Self(rawValue &+ UInt64(bitPattern: nanos))
        }

        /// Returns the signed duration from this instant to another, wrapping on overflow.
        @inlinable
        public func duration(to other: Self) -> Swift.Duration {
            // reason: typed-system bottom-out — `Clock.Nanoseconds.duration(to:)`
            // is the `InstantProtocol.duration(to:)` implementation for this
            // wrapper type. The canonical "two unsigned values → signed
            // difference via bit-pattern" pattern (wrapping `other &- self`
            // then `Int64(bitPattern:)`) is the necessary grounding into
            // `Swift.Duration.nanoseconds(_:)`. The wrapper IS the
            // implementation of this primitive operation; no typed
            // difference accessor exists at this layer.
            // swiftlint:disable:next bitpattern_rawvalue_chain_anti_pattern
            let diff = Int64(bitPattern: other.rawValue &- rawValue)
            return .nanoseconds(diff)
        }

        /// Orders two instants by their raw nanosecond count.
        @inlinable
        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}
