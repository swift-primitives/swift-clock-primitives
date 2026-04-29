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

import Synchronization

extension Clock.Continuous.Deadline {
    /// Atomic deadline storage for cross-thread coordination.
    ///
    /// Stores a `Clock.Continuous.Deadline?` via acquire/release
    /// atomics; the `.never` sentinel represents "no deadline". Internal
    /// storage is a raw `Atomic<UInt64>` for trivially-copyable atomicity;
    /// the public surface is the typed `Clock.Continuous.Deadline`.
    ///
    /// ## Usage
    /// ```swift
    /// let next = Clock.Continuous.Deadline.Next()
    ///
    /// // Producer (deadline scheduler)
    /// next.store(deadline)
    ///
    /// // Consumer (poll thread)
    /// if let deadline = next.value {
    ///     // use deadline for timeout
    /// }
    /// ```
    ///
    /// ## Thread Safety
    /// Sendable via internal `Atomic<UInt64>` synchronization.
    public final class Next: Sendable {
        let _value: Atomic<UInt64>

        /// Creates a new deadline storage (initially no deadline).
        public init() {
            self._value = Atomic(UInt64.max)
        }

        /// Updates the deadline.
        ///
        /// - Parameter deadline: The new deadline. Pass `.never` to
        ///   signal "no deadline".
        public func store(_ deadline: Clock.Continuous.Deadline) {
            _value.store(deadline.instant.nanoseconds, ordering: .releasing)
        }

        /// The current deadline, or `nil` if no deadline is set
        /// (sentinel: `Deadline.never`).
        public var value: Clock.Continuous.Deadline? {
            let ns = _value.load(ordering: .acquiring)
            guard ns != .max else { return nil }
            return Clock.Continuous.Deadline(Clock.Continuous.Instant(nanoseconds: ns))
        }
    }
}
