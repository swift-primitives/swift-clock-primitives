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
    ///     await clock.advance(by: .seconds(1))
    ///     XCTAssertEqual(model.count, 1)
    ///
    ///     await clock.advance(by: .seconds(4))
    ///     XCTAssertEqual(model.count, 5)
    ///
    ///     model.stopTimerButtonTapped()
    ///     await clock.run()
    /// }
    /// ```
    public final class Test: _Concurrency.Clock, @unchecked Sendable {
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
            struct Entry: Sendable {
                let id: UInt64
                let deadline: Instant
                let continuation: AsyncStream<Void>.Continuation
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

        public func sleep(
            until deadline: Instant,
            tolerance: Duration? = nil
        ) async throws {
            try Task.checkCancellation()

            // Generate ID and create stream inside lock
            let (id, stream): (UInt64, AsyncStream<Void>?) = state.withLock { st in
                guard deadline > st.now else { return (0, nil) }

                let id = st.nextID
                st.nextID &+= 1

                let stream = AsyncStream<Void> { continuation in
                    st.suspensions.append(State.Entry(
                        id: id,
                        deadline: deadline,
                        continuation: continuation
                    ))
                }
                return (id, stream)
            }

            guard let stream else { return }

            do {
                try await withTaskCancellationHandler {
                    for await _ in stream {
                        // Wait until stream finishes
                    }
                    try Task.checkCancellation()
                } onCancel: {
                    // Remove suspension and finish continuation outside lock scope
                    let toFinish: AsyncStream<Void>.Continuation? = state.withLock { st in
                        if let index = st.suspensions.firstIndex(where: { $0.id == id }) {
                            let c = st.suspensions[index].continuation
                            st.suspensions.remove(at: index)
                            return c
                        }
                        return nil
                    }
                    toFinish?.finish()
                }
            } catch {
                throw error
            }
        }

        /// Advances the test clock's internal time by the duration.
        ///
        /// This method is `async` because it cooperatively yields to allow suspended
        /// tasks to observe time changes and resume. The actual state mutation is
        /// synchronous; the async nature enables structured interleaving with sleepers.
        public func advance(by duration: Duration = .zero) async {
            let target = state.withLock { $0.now.advanced(by: duration) }
            await advance(to: target)
        }

        /// Advances the test clock's internal time to the deadline.
        public func advance(to deadline: Instant) async {
            while true {
                await Task.yield()

                // Collect continuations to finish outside the lock
                let toFinish: [AsyncStream<Void>.Continuation] = state.withLock { st in
                    guard st.now <= deadline else { return [] }

                    st.suspensions.sort { $0.deadline < $1.deadline }

                    guard let first = st.suspensions.first else {
                        st.now = deadline
                        return []
                    }

                    if first.deadline > deadline {
                        st.now = deadline
                        return []
                    }

                    // Advance to the first suspension's deadline
                    st.now = first.deadline

                    // Collect all suspensions at or before current time
                    var ready: [AsyncStream<Void>.Continuation] = []
                    while let head = st.suspensions.first, head.deadline <= st.now {
                        ready.append(head.continuation)
                        st.suspensions.removeFirst()
                    }

                    return ready
                }

                // Finish continuations outside the lock
                for c in toFinish {
                    c.finish()
                }

                // Check if we're done
                let isDone = state.withLock { $0.now >= deadline }
                if isDone && toFinish.isEmpty {
                    break
                }
            }

            await Task.yield()
        }

        /// Runs the clock until it has no scheduled sleeps left.
        ///
        /// This method advances the clock through all scheduled sleep deadlines
        /// in order, allowing each suspended task to resume naturally.
        ///
        /// - Parameter timeout: Maximum wall-clock time to wait for sleeps to complete.
        ///   If the timeout expires before all sleeps are processed, remaining sleeps
        ///   are force-finished (their continuations complete without error, but without
        ///   the clock advancing to their deadlines). This prevents test hangs but may
        ///   cause sleepers to observe unexpected timing.
        public func run(timeout duration: Swift.Duration = .milliseconds(500)) async {
            await Task.yield()

            let startTime = ContinuousClock.now
            while true {
                let isEmpty = state.withLock { $0.suspensions.isEmpty }
                if isEmpty { return }

                if startTime.duration(to: ContinuousClock.now) > duration {
                    // Timeout - collect and finish all remaining suspensions outside lock
                    let toFinish: [AsyncStream<Void>.Continuation] = state.withLock { st in
                        let cs = st.suspensions.map(\.continuation)
                        st.suspensions.removeAll()
                        return cs
                    }
                    for c in toFinish {
                        c.finish()
                    }
                    return
                }

                let nextDeadline: Instant? = state.withLock { st in
                    st.suspensions.sort { $0.deadline < $1.deadline }
                    return st.suspensions.first?.deadline
                }

                guard let nextDeadline else { return }

                let delta = state.withLock { $0.now.duration(to: nextDeadline) }
                await advance(by: delta)
            }
        }

        /// Throws an error if there are active sleeps on the clock.
        public func checkSuspension() async throws(Suspension.Error) {
            await Task.yield()
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
