import Clock_Primitives
import Testing

extension Clock.Test {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Integration {}
        @Suite(.serialized) struct Performance {}
    }
}

// MARK: - Unit

extension Clock.Test.Test.Unit {
    @Test
    func `init default now is zero offset`() {
        let clock = Clock.Test()
        #expect(clock.now.offset == .zero)
    }

    @Test
    func `init with custom now`() {
        let instant = Clock.Test.Instant(offset: .seconds(10))
        let clock = Clock.Test(now: instant)
        #expect(clock.now.offset == .seconds(10))
    }

    @Test
    func `minimumResolution defaults to zero`() {
        let clock = Clock.Test()
        #expect(clock.minimumResolution == .zero)
    }

    @Test
    func `minimumResolution setter`() {
        let clock = Clock.Test()
        clock.minimumResolution = .milliseconds(16)
        #expect(clock.minimumResolution == .milliseconds(16))
    }

    @Test
    func `advance by duration updates now`() {
        let clock = Clock.Test()
        clock.advance(by: .seconds(5))
        #expect(clock.now.offset == .seconds(5))
    }

    @Test
    func `advance to deadline updates now`() {
        let clock = Clock.Test()
        let target = Clock.Test.Instant(offset: .seconds(10))
        clock.advance(to: target)
        #expect(clock.now == target)
    }

    @Test
    func `sleep returns immediately when deadline already passed`() async throws {
        let clock = Clock.Test()
        clock.advance(by: .seconds(5))
        try await clock.sleep(until: .init(offset: .seconds(1)))
    }

    @Test
    func `Instant advanced by duration`() {
        let instant = Clock.Test.Instant(offset: .seconds(1))
        let advanced = instant.advanced(by: .seconds(2))
        #expect(advanced.offset == .seconds(3))
    }

    @Test
    func `Instant duration to other`() {
        let a = Clock.Test.Instant(offset: .seconds(1))
        let b = Clock.Test.Instant(offset: .seconds(4))
        #expect(a.duration(to: b) == .seconds(3))
    }

    @Test
    func `Instant ordering`() {
        let a = Clock.Test.Instant(offset: .seconds(1))
        let b = Clock.Test.Instant(offset: .seconds(2))
        #expect(a < b)
        #expect(!(b < a))
    }

    @Test
    func `Instant equality`() {
        let a = Clock.Test.Instant(offset: .seconds(5))
        let b = Clock.Test.Instant(offset: .seconds(5))
        #expect(a == b)
    }

    @Test
    func `Instant hashing: equal values produce equal hashes`() {
        let a = Clock.Test.Instant(offset: .seconds(5))
        let b = Clock.Test.Instant(offset: .seconds(5))
        #expect(a.hashValue == b.hashValue)
    }
}

// MARK: - Edge Case

extension Clock.Test.Test.`Edge Case` {
    @Test
    func `advance by zero`() {
        let clock = Clock.Test()
        clock.advance(by: .zero)
        #expect(clock.now.offset == .zero)
    }

    @Test
    func `Instant advanced by zero`() {
        let instant = Clock.Test.Instant(offset: .seconds(1))
        let advanced = instant.advanced(by: .zero)
        #expect(advanced == instant)
    }

    @Test
    func `Instant duration to self is zero`() {
        let instant = Clock.Test.Instant(offset: .seconds(3))
        #expect(instant.duration(to: instant) == .zero)
    }

    @Test
    func `Instant default offset is zero`() {
        let instant = Clock.Test.Instant()
        #expect(instant.offset == .zero)
    }

    @Test
    func `checkSuspension succeeds when no suspensions`() throws {
        let clock = Clock.Test()
        try clock.checkSuspension()
    }

    @Test
    func `sleep cancellation removes suspension`() async {
        let clock = Clock.Test()
        let task = Task.immediate {
            try await clock.sleep(until: .init(offset: .seconds(100)))
        }
        task.cancel()
        clock.run()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
    }
}

// MARK: - Integration

extension Clock.Test.Test.Integration {
    @Test
    func `sleep suspends until advance resumes it`() async throws {
        let clock = Clock.Test()
        let resumed = Locked(initialState: false)

        let task = Task.immediate {
            try await clock.sleep(until: .init(offset: .seconds(5)))
            resumed.withLock { $0 = true }
        }

        #expect(!resumed.withLock { $0 })

        clock.advance(by: .seconds(5))
        try await task.value
        #expect(resumed.withLock { $0 })
    }

    @Test @MainActor
    func `advance resumes multiple sleeps in order`() async throws {
        let clock = Clock.Test()
        let order = Locked(initialState: [Int]())

        let task1 = Task.immediate {
            try await clock.sleep(until: .init(offset: .seconds(2)))
            order.withLock { $0.append(1) }
        }

        let task2 = Task.immediate {
            try await clock.sleep(until: .init(offset: .seconds(4)))
            order.withLock { $0.append(2) }
        }

        // Step to each deadline in turn, draining the woken task before the next
        // advance. A single `advance(by:)` past both deadlines resumes both
        // continuations in deadline order, but their task *bodies* then run
        // concurrently — so the observed append order was a race (flaky ~1-in-8
        // under the full suite). Advancing to each deadline and awaiting the woken
        // task makes the ordering deterministic and strengthens the assertion:
        // `advance(to: 2s)` must wake task1 only (task2's 4s deadline is still in
        // the future), and `advance(to: 4s)` then wakes task2.
        clock.advance(to: .init(offset: .seconds(2)))
        try await task1.value
        clock.advance(to: .init(offset: .seconds(4)))
        try await task2.value
        #expect(order.withLock { $0 } == [1, 2])
    }

    @Test
    func `run processes all pending suspensions`() async throws {
        let clock = Clock.Test()
        let completed = Locked(initialState: false)

        let task = Task.immediate {
            try await clock.sleep(until: .init(offset: .seconds(10)))
            completed.withLock { $0 = true }
        }

        clock.run()
        try await task.value
        #expect(completed.withLock { $0 })
    }

    @Test
    func `checkSuspension throws when there are active suspensions`() async {
        let clock = Clock.Test()

        let task = Task.immediate {
            try await clock.sleep(until: .init(offset: .seconds(100)))
        }

        #expect(throws: Clock.Test.Suspension.Error.self) {
            try clock.checkSuspension()
        }

        task.cancel()
        clock.run()
        _ = await task.result
    }

    @Test
    func `advance(by:) composes: two advances sum correctly`() {
        let clock = Clock.Test()
        clock.advance(by: .seconds(3))
        clock.advance(by: .seconds(2))
        #expect(clock.now.offset == .seconds(5))
    }

    // MARK: - Ordering regression tests
    //
    // These verify the test clock resumes sleeps in DEADLINE order. They step the
    // clock to each deadline in turn, draining the woken task before the next
    // advance: a single advance past several deadlines resumes the continuations in
    // deadline order, but their task BODIES then run concurrently, so the observed
    // append order is a cross-platform race (flaky on macOS, deterministically wrong
    // on Linux — `[2, 3, 1]`). Incremental advance makes the ordering deterministic
    // without relying on executor FIFO behaviour.

    @Test @MainActor
    func `reverse-scheduled sleeps resume in deadline order`() async throws {
        let clock = Clock.Test()
        let order = Locked(initialState: [Int]())

        // Schedule in REVERSE deadline order: 3, 2, 1
        let task3 = Task.immediate {
            try await clock.sleep(until: .init(offset: .seconds(6)))
            order.withLock { $0.append(3) }
        }

        let task2 = Task.immediate {
            try await clock.sleep(until: .init(offset: .seconds(4)))
            order.withLock { $0.append(2) }
        }

        let task1 = Task.immediate {
            try await clock.sleep(until: .init(offset: .seconds(2)))
            order.withLock { $0.append(1) }
        }

        // Advance to each deadline in turn, draining the woken task first —
        // deterministic deadline-ordered waking regardless of schedule order.
        clock.advance(to: .init(offset: .seconds(2)))
        try await task1.value
        clock.advance(to: .init(offset: .seconds(4)))
        try await task2.value
        clock.advance(to: .init(offset: .seconds(6)))
        try await task3.value
        #expect(order.withLock { $0 } == [1, 2, 3])
    }

    @Test
    func `sequential advances resume correct subsets in order`() async throws {
        let clock = Clock.Test()
        let order = Locked(initialState: [Int]())

        let task1 = Task.immediate {
            try await clock.sleep(until: .init(offset: .seconds(1)))
            order.withLock { $0.append(1) }
        }

        let task2 = Task.immediate {
            try await clock.sleep(until: .init(offset: .seconds(3)))
            order.withLock { $0.append(2) }
        }

        let task3 = Task.immediate {
            try await clock.sleep(until: .init(offset: .seconds(5)))
            order.withLock { $0.append(3) }
        }

        // First advance resumes only task1
        clock.advance(by: .seconds(2))
        try await task1.value
        #expect(order.withLock { $0 } == [1])

        // Second advance resumes only task2
        clock.advance(by: .seconds(2))
        try await task2.value
        #expect(order.withLock { $0 } == [1, 2])

        // Third advance resumes only task3
        clock.advance(by: .seconds(2))
        try await task3.value
        #expect(order.withLock { $0 } == [1, 2, 3])
    }

    // MARK: - F-001 regression: deadline check and continuation registration
    // must be atomic
    //
    // Pre-fix, `sleep(until:)` checked `now < deadline` and registered the
    // continuation as two SEPARATE `state.withLock` acquisitions. A
    // concurrent `advance(to:)` landing in the gap between them sees no
    // registered entry yet, drains nothing, and the registration that
    // follows appends an entry whose deadline has already elapsed — nothing
    // but a LATER advance/run ever discovers it (in the worst case, nothing
    // ever does, and the sleeper hangs forever). This hammers `advance(to:)`
    // from several concurrently-running, genuinely unstructured tasks across
    // many rounds while sleepers race to register, to make real multi-core
    // interleaving land in that window.
    //
    // Sleepers and hammers are `Task.detached`, tracked via a `Locked`
    // counter and polled with a bounded real-time loop — not a
    // `withTaskGroup` — for the same reason as the F-002 test above: a
    // stranded (never-resumed) sleeper would otherwise hang the group's
    // implicit teardown forever, defeating the whole point of bounding this
    // stress test.
    @Test
    func `concurrent advance hammering never strands a sleeper`() async throws {
        // All rounds are launched CONCURRENTLY (not one after another) so the
        // machine has as many genuinely-simultaneous hammer/sleeper pairs in
        // flight as possible at any given instant — maximizing the chance
        // that real multi-core preemption lands inside the pre-fix gap.
        let rounds = 300
        let sleepersPerRound = 8
        let hammerTasksPerRound = 4
        let overallBudget = Duration.milliseconds(500)

        struct Round {
            let clock: Clock.Test
            let deadline: Clock.Test.Instant
            let completed: Locked<Int>
            let stopHammering: Locked<Bool>
        }

        let allRounds = (0..<rounds).map { _ in
            Round(
                clock: Clock.Test(),
                deadline: Clock.Test.Instant(offset: .milliseconds(1)),
                completed: Locked<Int>(initialState: 0),
                stopHammering: Locked<Bool>(initialState: false)
            )
        }

        for round in allRounds {
            for _ in 0..<hammerTasksPerRound {
                Task.detached {
                    var iteration = 0
                    while !round.stopHammering.withLock({ $0 }) {
                        round.clock.advance(to: round.deadline)
                        iteration += 1
                        if iteration % 64 == 0 { await Task.yield() }
                    }
                }
            }
            for _ in 0..<sleepersPerRound {
                Task.detached {
                    try? await round.clock.sleep(until: round.deadline)
                    round.completed.withLock { $0 += 1 }
                }
            }
        }

        let wallClock = ContinuousClock()
        let start = wallClock.now
        var allWoke = false
        while wallClock.now - start < overallBudget {
            if allRounds.allSatisfy({ $0.completed.withLock { $0 } == sleepersPerRound }) {
                allWoke = true
                break
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        for round in allRounds {
            round.stopHammering.withLock { $0 = true }
        }

        if !allWoke {
            let strandedRounds = allRounds.enumerated().filter { _, round in
                round.completed.withLock { $0 } != sleepersPerRound
            }
            Issue.record(
                "\(strandedRounds.count)/\(rounds) rounds left at least one sleeper stranded within \(overallBudget) of racing advance(to:) calls — lost wakeup (F-001 regression)"
            )
        }
    }

    @Test @MainActor
    func `cancelled task does not disrupt ordering of remaining sleeps`() async throws {
        let clock = Clock.Test()
        let order = Locked(initialState: [Int]())

        let task1 = Task.immediate {
            try await clock.sleep(until: .init(offset: .seconds(2)))
            order.withLock { $0.append(1) }
        }

        let taskCancelled = Task.immediate {
            try await clock.sleep(until: .init(offset: .seconds(3)))
            order.withLock { $0.append(99) }
        }

        let task2 = Task.immediate {
            try await clock.sleep(until: .init(offset: .seconds(4)))
            order.withLock { $0.append(2) }
        }

        // Cancel the middle task before advancing
        taskCancelled.cancel()

        // Advance to each deadline in turn (deterministic). `advance(to: 4s)` wakes
        // task2 and resumes the cancelled task, which throws CancellationError
        // instead of appending 99.
        clock.advance(to: .init(offset: .seconds(2)))
        try await task1.value
        clock.advance(to: .init(offset: .seconds(4)))
        _ = await taskCancelled.result
        try await task2.value

        // 99 must not appear; 1 and 2 must be in order
        #expect(order.withLock { $0 } == [1, 2])
    }
}
