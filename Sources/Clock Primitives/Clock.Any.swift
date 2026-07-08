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

// Type erasure over `_Concurrency.Clock` plus the `async` `sleep` witness.
// Embedded Swift has no `_Concurrency` module, so this surface is excluded
// there; the non-async time types (Instant, Deadline, Duration arithmetic)
// remain available under Embedded.
#if !hasFeature(Embedded)

    extension Clock {
        // WHY: Category D — structural Sendable workaround (SP-7).
        // WHY: Type-erased clock struct. Stored fields are @Sendable closures +
        // WHY: generic D: DurationProtocol & Hashable (without Sendable). No
        // WHY: synchronization, no ~Copyable. @unchecked exists because stored
        // WHY: function-type properties and the generic D block structural inference.
        // WHEN TO REMOVE: When compiler gains structural Sendable inference through
        // WHEN TO REMOVE: @Sendable closure storage and generic parameters.
        // TRACKING: unsafe-audit-findings.md Category D SP-7.
        /// A type-erased clock that wraps another clock.
        ///
        /// Use this type when you need to store or pass clocks with different
        /// underlying types but the same duration type. This is particularly
        /// useful when working with APIs that require concrete clock types
        /// rather than existentials.
        ///
        /// ## Example
        ///
        /// ```swift
        /// let clock: Clock.`Any`<Duration> = Clock.`Any`(ContinuousClock())
        /// try await clock.sleep(for: .seconds(1))
        /// ```
        public struct `Any`<D: DurationProtocol & Hashable>: _Concurrency.Clock, @unchecked Sendable {
            /// The type-erased instant of the wrapped clock.
            public struct Instant: InstantProtocol, Sendable {
                fileprivate let _box: Box
            }

            private let _now: @Sendable () -> Instant
            private let _minimumResolution: @Sendable () -> D
            // Mirrors the `_Concurrency.Clock.sleep` requirement, which is declared
            // untyped `async throws`; the stored thunk must match that signature, so
            // [API-ERR-001] typed throws cannot apply here.
            // swiftlint:disable:next typed_throws_required
            private let _sleep: nonisolated(nonsending) @Sendable (Instant, D?) async throws -> Void

            /// The current instant of the wrapped clock.
            public var now: Instant { _now() }
            /// The minimum resolution of the wrapped clock.
            public var minimumResolution: D { _minimumResolution() }

            /// Creates a type-erased clock from a concrete clock.
            ///
            /// - Parameter clock: The clock to wrap.
            public init<C: _Concurrency.Clock>(_ clock: C) where C.Duration == D, C: Sendable, C.Instant: Sendable {
                self._now = {
                    Instant(_box: ConcreteBox(clock.now))
                }
                self._minimumResolution = { clock.minimumResolution }
                self._sleep = { deadline, tolerance in
                    guard let box = deadline._box as? ConcreteBox<C.Instant, D> else {
                        preconditionFailure("Mismatched clock instant types")
                    }
                    try await clock.sleep(until: box.instant, tolerance: tolerance)
                }
            }

            // Witnesses `_Concurrency.Clock.sleep`, declared untyped `async throws`;
            // a typed-throws witness would not satisfy the requirement, so
            // [API-ERR-001] is structurally inapplicable here.
            // swiftlint:disable typed_throws_required
            /// Sleeps until the specified deadline.
            ///
            /// - Parameters:
            ///   - deadline: The instant until which to sleep.
            ///   - tolerance: The allowed tolerance for the sleep duration.
            /// - Throws: Any error thrown by the wrapped clock's `sleep`.
            nonisolated(nonsending)
                public func sleep(
                    until deadline: Instant,
                    tolerance: D? = nil
                ) async throws
            {
                // swiftlint:enable typed_throws_required
                try await _sleep(deadline, tolerance)
            }
        }
    }

    extension Clock.`Any`.Instant {
        /// Returns the instant advanced by the given duration.
        public func advanced(by duration: D) -> Self {
            Self(_box: _box.advanced(by: duration))
        }

        /// Returns the duration from this instant to another.
        public func duration(to other: Self) -> D {
            _box.duration(to: other._box)
        }

        /// Orders two instants via the wrapped instant's comparison.
        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs._box.compare(lhs._box, rhs._box)
        }

        /// Compares two instants via the wrapped instant's equality.
        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs._box.equals(lhs._box, rhs._box)
        }

        /// Hashes the instant via the wrapped instant.
        public func hash(into hasher: inout Hasher) {
            _box.hash(into: &hasher)
        }

        // WHY: Category D — structural Sendable workaround (SP-7).
        // WHY: Empty abstract class with no stored state. @unchecked enables
        // WHY: the ConcreteBox subclass hierarchy to propagate Sendable through D.
        // WHEN TO REMOVE: When compiler gains structural inference through class hierarchies.
        // TRACKING: unsafe-audit-findings.md Category D SP-7.
        /// Type-erased box for instant storage.
        fileprivate class Box: @unchecked Sendable {
            func advanced(by duration: D) -> Box { fatalError("Must be overridden") }
            func duration(to other: Box) -> D { fatalError("Must be overridden") }
            func compare(_ lhs: Box, _ rhs: Box) -> Bool { fatalError("Must be overridden") }
            func equals(_ lhs: Box, _ rhs: Box) -> Bool { fatalError("Must be overridden") }
            func hash(into hasher: inout Hasher) { fatalError("Must be overridden") }
        }
    }

    private final class ConcreteBox<
        I: InstantProtocol & Hashable & Sendable,
        D: DurationProtocol & Hashable
    >: Clock.`Any`<D>.Instant.Box where I.Duration == D {
        // WHY: Category D — structural Sendable workaround (SP-7).
        // WHY: Immutable `let instant: I` after init. Sendable inherited from Box base.
        // TRACKING: unsafe-audit-findings.md Category D SP-7.
        let instant: I

        init(_ instant: I) {
            self.instant = instant
        }

        override func advanced(by duration: D) -> Clock.`Any`<D>.Instant.Box {
            ConcreteBox(instant.advanced(by: duration))
        }

        override func duration(to other: Clock.`Any`<D>.Instant.Box) -> D {
            guard let other = other as? ConcreteBox<I, D> else {
                preconditionFailure("Mismatched clock instant types")
            }
            return instant.duration(to: other.instant)
        }

        override func compare(
            _ lhs: Clock.`Any`<D>.Instant.Box,
            _ rhs: Clock.`Any`<D>.Instant.Box
        ) -> Bool {
            guard let lhs = lhs as? ConcreteBox<I, D>, let rhs = rhs as? ConcreteBox<I, D> else {
                preconditionFailure("Mismatched clock instant types")
            }
            return lhs.instant < rhs.instant
        }

        override func equals(
            _ lhs: Clock.`Any`<D>.Instant.Box,
            _ rhs: Clock.`Any`<D>.Instant.Box
        ) -> Bool {
            guard let lhs = lhs as? ConcreteBox<I, D>, let rhs = rhs as? ConcreteBox<I, D> else {
                preconditionFailure("Mismatched clock instant types")
            }
            return lhs.instant == rhs.instant
        }

        override func hash(into hasher: inout Hasher) {
            hasher.combine(instant)
        }
    }

#endif
