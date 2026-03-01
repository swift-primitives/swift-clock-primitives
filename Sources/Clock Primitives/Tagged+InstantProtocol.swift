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

// MARK: - InstantProtocol conformance

extension Tagged: @retroactive InstantProtocol where RawValue: InstantProtocol {
    public typealias Duration = RawValue.Duration

    @inlinable
    public func advanced(by duration: RawValue.Duration) -> Self {
        Self(__unchecked: (), rawValue.advanced(by: duration))
    }

    @inlinable
    public func duration(to other: Self) -> RawValue.Duration {
        rawValue.duration(to: other.rawValue)
    }
}

// MARK: - Affine arithmetic operators

extension Tagged where RawValue: InstantProtocol, RawValue.Duration == Swift.Duration {
    /// Advances an instant by a duration.
    @inlinable
    public static func + (lhs: Self, rhs: Swift.Duration) -> Self {
        Self(__unchecked: (), lhs.rawValue.advanced(by: rhs))
    }

    /// Advances an instant by a duration (reversed operands).
    @inlinable
    public static func + (lhs: Swift.Duration, rhs: Self) -> Self {
        Self(__unchecked: (), rhs.rawValue.advanced(by: lhs))
    }

    /// Advances an instant by a duration in place.
    @inlinable
    public static func += (lhs: inout Self, rhs: Swift.Duration) {
        lhs = lhs + rhs
    }

    /// Retreats an instant by a duration.
    @inlinable
    public static func - (lhs: Self, rhs: Swift.Duration) -> Self {
        Self(__unchecked: (), lhs.rawValue.advanced(by: .zero - rhs))
    }

    /// Retreats an instant by a duration in place.
    @inlinable
    public static func -= (lhs: inout Self, rhs: Swift.Duration) {
        lhs = lhs - rhs
    }

    /// Returns the duration between two instants.
    @inlinable
    public static func - (lhs: Self, rhs: Self) -> Swift.Duration {
        rhs.rawValue.duration(to: lhs.rawValue)
    }
}
