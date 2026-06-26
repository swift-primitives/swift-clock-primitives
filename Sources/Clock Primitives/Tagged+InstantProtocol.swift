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

public import Carrier_Primitives

// MARK: - InstantProtocol conformance
//
// All extensions in this file constrain `Underlying: InstantProtocol &
// Carrier.`Protocol`` with `Underlying.Underlying == Underlying` (trivial
// self-carrier). The Carrier conformance is required to access
// `tagged.underlying` and the public `Tagged(_:)` initializer; the
// trivial-self constraint keeps the cascade flat so that the public init's
// `Self.Underlying` parameter is the same `Underlying` we operate on.

extension Tagged: @retroactive InstantProtocol
where Underlying: InstantProtocol & Carrier.`Protocol`, Underlying.Underlying == Underlying {
    /// The underlying instant's duration type.
    public typealias Duration = Underlying.Duration

    /// Returns the tagged instant advanced by the given duration.
    @inlinable
    public func advanced(by duration: Underlying.Duration) -> Self {
        Self(underlying.advanced(by: duration))
    }

    /// Returns the duration from this tagged instant to another.
    @inlinable
    public func duration(to other: Self) -> Underlying.Duration {
        underlying.duration(to: other.underlying)
    }
}

// MARK: - Swift.Duration-concrete overloads

/// Concrete-typed `advanced(by:)` and `duration(to:)` overloads for the common
/// case where the wrapped `Underlying`'s `InstantProtocol.Duration` is
/// `Swift.Duration`. Without these, the generic conformance above takes
/// `Underlying.Duration` — Swift's contextual inference cannot resolve
/// `.seconds(1)` / `.milliseconds(10)` through the associated-type projection,
/// even when the projection is concretely `Swift.Duration`. With the specialized
/// parameter type, Swift resolves `.seconds` directly on `Swift.Duration` and
/// prefers these overloads (more specific) at the call site.

extension Tagged
where
    Underlying: InstantProtocol & Carrier.`Protocol`,
    Underlying.Underlying == Underlying,
    Underlying.Duration == Swift.Duration
{
    /// Returns the tagged instant advanced by the given `Swift.Duration`.
    @inlinable
    public func advanced(by duration: Swift.Duration) -> Self {
        Self(underlying.advanced(by: duration))
    }

    /// Returns the `Swift.Duration` from this tagged instant to another.
    @inlinable
    public func duration(to other: Self) -> Swift.Duration {
        underlying.duration(to: other.underlying)
    }
}

// MARK: - Affine arithmetic operators

extension Tagged
where
    Underlying: InstantProtocol & Carrier.`Protocol`,
    Underlying.Underlying == Underlying,
    Underlying.Duration == Swift.Duration
{
    /// Advances an instant by a duration.
    @inlinable
    public static func + (lhs: Self, rhs: Swift.Duration) -> Self {
        Self(lhs.underlying.advanced(by: rhs))
    }

    /// Advances an instant by a duration (reversed operands).
    @inlinable
    public static func + (lhs: Swift.Duration, rhs: Self) -> Self {
        Self(rhs.underlying.advanced(by: lhs))
    }

    /// Advances an instant by a duration in place.
    @inlinable
    public static func += (lhs: inout Self, rhs: Swift.Duration) {
        lhs = lhs + rhs
    }

    /// Retreats an instant by a duration.
    @inlinable
    public static func - (lhs: Self, rhs: Swift.Duration) -> Self {
        Self(lhs.underlying.advanced(by: .zero - rhs))
    }

    /// Retreats an instant by a duration in place.
    @inlinable
    public static func -= (lhs: inout Self, rhs: Swift.Duration) {
        lhs = lhs - rhs
    }

    /// Returns the duration between two instants.
    @inlinable
    public static func - (lhs: Self, rhs: Self) -> Swift.Duration {
        rhs.underlying.duration(to: lhs.underlying)
    }
}
