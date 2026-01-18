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

import Synchronization

extension Clock {
    /// A clock that does not suspend when sleeping.
    ///
    /// This clock is useful for squashing all of time down to a single instant,
    /// forcing any `sleep`s to execute immediately. This is particularly useful
    /// for SwiftUI previews where you want to see the final state without waiting.
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct Feature_Previews: PreviewProvider {
    ///     static var previews: some View {
    ///         Feature(clock: Clock.Immediate())
    ///     }
    /// }
    /// ```
    public final class Immediate: _Concurrency.Clock, @unchecked Sendable {
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

        private struct State: Sendable {
            var now: Instant
            var minimumResolution: Duration
        }

        private let state: Mutex<State>

        public init(now: Instant = .init()) {
            self.state = Mutex(State(now: now, minimumResolution: .zero))
        }

        public var now: Instant {
            state.withLock { $0.now }
        }

        public var minimumResolution: Duration {
            get { state.withLock { $0.minimumResolution } }
            set { state.withLock { $0.minimumResolution = newValue } }
        }

        /// Sleeps until the specified deadline (executes immediately).
        ///
        /// - Parameters:
        ///   - deadline: The instant until which to sleep.
        ///   - tolerance: The allowed tolerance for the sleep duration.
        public func sleep(
            until deadline: Instant,
            tolerance: Duration? = nil
        ) async throws {
            try Task.checkCancellation()
            state.withLock { $0.now = deadline }
            // Yield to allow cooperative scheduling fairness, not to simulate time passing
            await Task.yield()
        }
    }
}
