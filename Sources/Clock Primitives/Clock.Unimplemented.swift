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

// Conforms to `_Concurrency.Clock` and witnesses the `async` `sleep`
// requirement. Embedded Swift has no `_Concurrency` module, so this clock is
// excluded there.
#if !hasFeature(Embedded)

    extension Clock {
        /// A clock that triggers a failure if any of its endpoints are invoked.
        ///
        /// This clock is useful for proving that a particular code path does not
        /// use time-based functionality. If any sleep is invoked on this clock,
        /// it will trigger a precondition failure.
        ///
        /// ## Example
        ///
        /// ```swift
        /// func testNonTimerPath() {
        ///     let model = FeatureModel(clock: Clock.Unimplemented())
        ///     // If this path accidentally uses the clock, the test will fail
        ///     model.performNonTimerAction()
        /// }
        /// ```
        public struct Unimplemented: _Concurrency.Clock, Sendable {
            /// Creates an unimplemented clock.
            public init() {}
        }
    }

    extension Clock.Unimplemented {
        /// The instant type for unimplemented clock.
        public typealias Instant = Tagged<Self, Clock.Offset>

        /// The current instant (always the zero offset).
        public var now: Instant { .init() }
        /// The smallest measurable duration (zero).
        public var minimumResolution: Duration { .zero }

        // Witnesses `_Concurrency.Clock.sleep`, declared untyped `async throws`;
        // a typed-throws witness would not satisfy the requirement, so
        // [API-ERR-001] is structurally inapplicable here.
        // swiftlint:disable typed_throws_required
        /// Sleeps until the specified deadline (triggers precondition failure).
        ///
        /// - Parameters:
        ///   - deadline: The instant until which to sleep.
        ///   - tolerance: The allowed tolerance for the sleep duration.
        /// - Throws: Never returns; always triggers a precondition failure.
        nonisolated(nonsending)
            public func sleep(
                until deadline: Instant,
                tolerance: Duration? = nil
            ) async throws
        {
            // swiftlint:enable typed_throws_required
            preconditionFailure(
                """
                Unimplemented clock sleep was invoked. This indicates a code path \
                that was not expected to use time-based functionality.
                """
            )
        }
    }

#endif
