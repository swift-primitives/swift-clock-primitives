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
    /// Duration-offset point in time.
    ///
    /// Base storage type for virtual clocks (Test, Immediate, Unimplemented).
    /// Stores an offset from an arbitrary zero point as a `Duration`.
    ///
    /// Not used directly — clock instant types are `Tagged<ClockType, Clock.Offset>`.
    public struct Offset: InstantProtocol, Sendable, Hashable, Comparable {
        /// The duration type measuring distance between offsets.
        public typealias Duration = Swift.Duration

        /// Offset from zero.
        public let rawValue: Swift.Duration

        /// Creates an offset from a duration past zero.
        @inlinable
        public init(_ rawValue: Swift.Duration = .zero) { self.rawValue = rawValue }

        /// Returns the offset advanced by the given duration.
        @inlinable
        public func advanced(by duration: Swift.Duration) -> Self {
            Self(rawValue + duration)
        }

        /// Returns the duration from this offset to another.
        @inlinable
        public func duration(to other: Self) -> Swift.Duration {
            other.rawValue - rawValue
        }

        /// Orders two offsets by their raw duration.
        @inlinable
        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}
