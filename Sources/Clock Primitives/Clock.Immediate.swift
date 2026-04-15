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
    /// ## Safety Invariant
    ///
    /// Internal `Mutex<State>` serializes all access. All reads and mutations
    /// go through `state.withLock`.
    ///
    /// ## Intended Use
    ///
    /// - SwiftUI preview clocks with instant time advancement.
    /// - Testing time-dependent logic without real delays.
    ///
    /// ## Non-Goals
    ///
    /// - Not a real-time clock; time only advances explicitly.
    public final class Immediate: _Concurrency.Clock, @unsafe @unchecked Sendable {
        /// The instant type for immediate clock measurements.
        public typealias Instant = Tagged<Immediate, Clock.Offset>

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
        /// This method is `nonisolated(nonsending)` to preserve the caller's
        /// isolation context. Because an immediate clock never truly suspends,
        /// there is no yield point and no thread hop.
        ///
        /// - Parameters:
        ///   - deadline: The instant until which to sleep.
        ///   - tolerance: The allowed tolerance for the sleep duration.
        nonisolated(nonsending)
        public func sleep(
            until deadline: Instant,
            tolerance: Duration? = nil
        ) async throws {
            try Task.checkCancellation()
            state.withLock { $0.now = deadline }
        }
    }
}
