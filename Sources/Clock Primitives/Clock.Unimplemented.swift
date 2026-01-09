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
        public struct Instant: InstantProtocol, Sendable, Hashable {
            public let offset: Duration

            public init(offset: Duration = .zero) {
                self.offset = offset
            }

            public func advanced(by duration: Duration) -> Self {
                .init(offset: offset + duration)
            }

            public func duration(to other: Self) -> Duration {
                other.offset - offset
            }

            public static func < (lhs: Self, rhs: Self) -> Bool {
                lhs.offset < rhs.offset
            }
        }

        public var now: Instant { .init() }
        public var minimumResolution: Duration { .zero }

        public init() {}

        public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
            preconditionFailure(
                """
                Unimplemented clock sleep was invoked. This indicates a code path \
                that was not expected to use time-based functionality.
                """
            )
        }
    }
}
