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

// Conforms to `_Concurrency.Clock`, witnesses the `async` `sleep` requirement,
// and parks suspended tasks on `CheckedContinuation`s. Embedded Swift has no
// `_Concurrency` module, so this clock is excluded there.
#if !hasFeature(Embedded)

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
        /// ## Safety Invariant
        ///
        /// Internal `Mutex<State>` serializes all access. All reads and mutations
        /// go through `state.withLock`.
        ///
        /// ## Intended Use
        ///
        /// - Deterministic testing of time-dependent logic.
        /// - Explicit time advancement with `advance(by:)` and `run()`.
        ///
        /// ## Non-Goals
        ///
        /// - Not a real-time clock; time only advances explicitly.
        public final class Test: _Concurrency.Clock, @unsafe @unchecked Sendable {
            private let state: Mutex<State>

            /// Creates a test clock starting at the given instant.
            public init(now: Instant = .init()) {
                self.state = Mutex(
                    State(
                        now: now,
                        minimumResolution: .zero,
                        nextID: 0,
                        suspensions: []
                    )
                )
            }
        }
    }

    extension Clock.Test {
        /// The instant type for test clock measurements.
        public typealias Instant = Tagged<Clock.Test, Clock.Offset>

        fileprivate struct State: Sendable {
            var now: Instant
            var minimumResolution: Duration
            var nextID: UInt64
            var suspensions: [Entry]
        }
    }

    extension Clock.Test.State {
        struct Entry: Sendable {
            let id: UInt64
            let deadline: Clock.Test.Instant
            let continuation: CheckedContinuation<Void, Never>
        }
    }

    extension Clock.Test {
        /// The current instant, moved only by explicit advancement.
        public var now: Instant {
            state.withLock { $0.now }
        }

        /// The smallest measurable duration.
        public var minimumResolution: Duration {
            get { state.withLock { $0.minimumResolution } }
            set { state.withLock { $0.minimumResolution = newValue } }
        }

        // Witnesses `_Concurrency.Clock.sleep`, declared untyped `async throws`;
        // a typed-throws witness would not satisfy the requirement, so
        // [API-ERR-001] is structurally inapplicable here.
        // swiftlint:disable typed_throws_required
        /// Suspends until the test clock is advanced past the deadline.
        ///
        /// The task stays suspended until `advance(by:)`, `advance(to:)`, or
        /// `run()` moves the clock to or past `deadline`.
        ///
        /// - Parameters:
        ///   - deadline: The instant until which to sleep.
        ///   - tolerance: The allowed tolerance for the sleep duration.
        /// - Throws: `CancellationError` if the task is cancelled.
        nonisolated(nonsending)
            public func sleep(
                until deadline: Instant,
                tolerance: Duration? = nil
            ) async throws
        {
            // swiftlint:enable typed_throws_required
            try Task.checkCancellation()

            // F-001: the deadline re-check and the continuation append MUST
            // happen inside the SAME `withLock` closure. Splitting them into
            // two separate lock acquisitions (as a prior revision did) opens
            // a window in which a concurrent `advance(to:)` can run between
            // the check and the append: it observes nothing registered yet,
            // drains nothing, and the append that follows then stores an
            // entry whose deadline has already elapsed — nothing but a LATER
            // advance/run would ever discover it, and in the worst case
            // nothing ever does. Re-checking `now < deadline` under the same
            // lock that performs the append closes that window: either this
            // call observes the deadline has already passed and resumes
            // immediately, or it registers atomically with respect to every
            // other `state.withLock` critical section (including
            // `advance`/`run`), so no interleaving can produce a stale,
            // unreachable entry.
            //
            // F-002: cancelling the sleeping task must wake it promptly, not
            // only when a LATER `advance`/`run` happens to sweep past this
            // entry's deadline (or never, if none ever comes). `id` is
            // reserved up front as a plain immutable value, known to both the
            // registration closure below and the cancellation handler without
            // any extra synchronization: `withTaskCancellationHandler`'s
            // `onCancel` closure removes the entry (if still present) under
            // the SAME `state` lock and resumes it itself. Racing
            // `onCancel` against `advance`/`run` resuming the same entry is
            // safe because both paths go through `firstIndex(where:)` +
            // `remove(at:)` under that one lock: whichever runs first
            // consumes the entry, the other finds it already gone and is a
            // no-op, so the continuation is resumed exactly once. The
            // `Task.isCancelled` check inside the atomic decision closes the
            // remaining gap where cancellation lands after this call reserves
            // `id` but before it decides whether to register: in that case it
            // resumes immediately instead of registering an entry `onCancel`
            // will never see (registered too late to be found, since
            // `onCancel` may already have run and found nothing).
            let id = state.withLock { st -> UInt64 in
                let id = st.nextID
                st.nextID &+= 1
                return id
            }

            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    let resumeImmediately = state.withLock { st -> Bool in
                        guard !Task.isCancelled, st.now < deadline else { return true }
                        st.suspensions.append(
                            State.Entry(
                                id: id,
                                deadline: deadline,
                                continuation: continuation
                            )
                        )
                        return false
                    }
                    if resumeImmediately {
                        continuation.resume()
                    }
                }
            } onCancel: {
                let toResume: CheckedContinuation<Void, Never>? = state.withLock { st in
                    guard let index = st.suspensions.firstIndex(where: { $0.id == id }) else {
                        return nil
                    }
                    return st.suspensions.remove(at: index).continuation
                }
                toResume?.resume()
            }

            try Task.checkCancellation()
        }

        /// Advances the test clock's internal time by the duration.
        ///
        /// - Parameter duration: The duration to advance by.
        public func advance(by duration: Duration = .zero) {
            // Fold the target-time read and the advance into a single
            // `state.withLock` critical section (mirroring F-001's fold in
            // `sleep(until:)`). The prior two-phase form read `now` under one
            // lock and then re-locked inside `advance(to:)`: under concurrent
            // `advance(by:)` callers this let two racers compute a target
            // from the same stale `now`, or apply a smaller target after a
            // larger one had already moved `now` forward, silently
            // collapsing or reordering advances. Computing `target` from
            // `st.now` inside the same critical section that mutates `now`
            // and drains `suspensions` closes that window; resumption still
            // happens outside the lock, matching `advance(to:)`/`run()`.
            let toResume: [CheckedContinuation<Void, Never>] = state.withLock { st in
                let deadline = st.now.advanced(by: duration)
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

    extension Clock.Test {
        /// Namespace for suspension-related types.
        public enum Suspension {}
    }

    extension Clock.Test.Suspension {
        /// An error that indicates there are actively suspending sleeps scheduled on the clock.
        public struct Error: Swift.Error, Sendable {}
    }

#endif
