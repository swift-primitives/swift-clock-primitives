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
    /// A clock whose time can be controlled in a deterministic manner.
    ///
    /// This clock is useful for testing how the flow of time affects asynchronous
    /// and concurrent code. This includes any code that makes use of `sleep` or
    /// any time-based async operators, such as timers, debounce, throttle, timeout.
    ///
    /// ## Example
    ///
    /// ```swift
    /// func testTimer() async {
    ///     let clock = Clock.Test()
    ///     let model = FeatureModel(clock: clock)
    ///
    ///     XCTAssertEqual(model.count, 0)
    ///     model.startTimerButtonTapped()
    ///
    ///     clock.advance(by: .seconds(1))
    ///     XCTAssertEqual(model.count, 1)
    ///
    ///     clock.advance(by: .seconds(4))
    ///     XCTAssertEqual(model.count, 5)
    ///
    ///     model.stopTimerButtonTapped()
    ///     clock.run()
    /// }
    /// ```
    public final class Test: _Concurrency.Clock, @unchecked Sendable {
        /// The instant type for test clock measurements.
        public typealias Instant = Tagged<Test, Clock.Offset>

        private struct State: Sendable {
            struct Entry: Sendable {
                let id: UInt64
                let deadline: Instant
                let continuation: CheckedContinuation<Void, Never>
            }

            var now: Instant
            var minimumResolution: Duration
            var nextID: UInt64
            var suspensions: [Entry]
        }

        private let state: Mutex<State>

        public init(now: Instant = .init()) {
            self.state = Mutex(State(
                now: now,
                minimumResolution: .zero,
                nextID: 0,
                suspensions: []
            ))
        }

        public var now: Instant {
            state.withLock { $0.now }
        }

        public var minimumResolution: Duration {
            get { state.withLock { $0.minimumResolution } }
            set { state.withLock { $0.minimumResolution = newValue } }
        }

        nonisolated(nonsending)
        public func sleep(
            until deadline: Instant,
            tolerance: Duration? = nil
        ) async throws {
            try Task.checkCancellation()

            let shouldSuspend = state.withLock { $0.now < deadline }
            guard shouldSuspend else { return }

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                state.withLock { st in
                    let id = st.nextID
                    st.nextID &+= 1
                    st.suspensions.append(State.Entry(
                        id: id,
                        deadline: deadline,
                        continuation: continuation
                    ))
                }
            }

            try Task.checkCancellation()
        }

        /// Advances the test clock's internal time by the duration.
        ///
        /// - Parameter duration: The duration to advance by.
        public func advance(by duration: Duration = .zero) {
            let target = state.withLock { $0.now.advanced(by: duration) }
            advance(to: target)
        }

        /// Advances the test clock's internal time to the deadline.
        ///
        /// - Parameter deadline: The instant to advance to.
        public func advance(to deadline: Instant) {
            let toResume: [CheckedContinuation<Void, Never>] = state.withLock { st in
                st.now = deadline
                st.suspensions.sort { $0.deadline < $1.deadline }
                var ready: [CheckedContinuation<Void, Never>] = []
                while let head = st.suspensions.first, head.deadline <= deadline {
                    ready.append(head.continuation)
                    st.suspensions.removeFirst()
                }
                return ready
            }
            for c in toResume { c.resume() }
        }

        /// Runs the clock until it has no scheduled sleeps left.
        ///
        /// This method advances the clock through all scheduled sleep deadlines,
        /// resuming every suspended task.
        public func run() {
            let toResume: [CheckedContinuation<Void, Never>] = state.withLock { st in
                st.suspensions.sort { $0.deadline < $1.deadline }
                if let last = st.suspensions.last { st.now = last.deadline }
                let all = st.suspensions.map(\.continuation)
                st.suspensions.removeAll()
                return all
            }
            for c in toResume { c.resume() }
        }

        /// Throws an error if there are active sleeps on the clock.
        public func checkSuspension() throws(Suspension.Error) {
            let hasActive = state.withLock { !$0.suspensions.isEmpty }
            guard !hasActive else {
                throw Suspension.Error()
            }
        }
    }
}

extension Clock.Test {
    /// Namespace for suspension-related types.
    public enum Suspension {}
}

extension Clock.Test.Suspension {
    /// An error that indicates there are actively suspending sleeps scheduled on the clock.
    public struct Error: Swift.Error, Sendable {}
}
