import Testing
import Clock_Primitives
import os

extension Clock.Test {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct EdgeCase {}
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
    func `advance by duration updates now`() async {
        let clock = Clock.Test()
        await clock.advance(by: .seconds(5))
        #expect(clock.now.offset == .seconds(5))
    }

    @Test
    func `advance to deadline updates now`() async {
        let clock = Clock.Test()
        let target = Clock.Test.Instant(offset: .seconds(10))
        await clock.advance(to: target)
        #expect(clock.now == target)
    }

    @Test
    func `sleep returns immediately when deadline already passed`() async throws {
        let clock = Clock.Test()
        await clock.advance(by: .seconds(5))
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

extension Clock.Test.Test.EdgeCase {
    @Test
    func `advance by zero`() async {
        let clock = Clock.Test()
        await clock.advance(by: .zero)
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
    func `checkSuspension succeeds when no suspensions`() async throws {
        let clock = Clock.Test()
        try await clock.checkSuspension()
    }

    @Test
    func `sleep cancellation removes suspension`() async {
        let clock = Clock.Test()
        let task = Task {
            try await clock.sleep(until: .init(offset: .seconds(100)))
        }
        task.cancel()
        _ = await task.result

        try? await clock.checkSuspension()
    }
}

// MARK: - Integration

extension Clock.Test.Test.Integration {
    @Test
    func `sleep suspends until advance resumes it`() async throws {
        let clock = Clock.Test()
        let resumed = OSAllocatedUnfairLock(initialState: false)

        let task = Task {
            try await clock.sleep(until: .init(offset: .seconds(5)))
            resumed.withLock { $0 = true }
        }

        await Task.yield()
        await Task.yield()
        #expect(!resumed.withLock { $0 })

        await clock.advance(by: .seconds(5))
        try await task.value
        #expect(resumed.withLock { $0 })
    }

    @Test
    func `advance resumes multiple sleeps in order`() async throws {
        let clock = Clock.Test()
        let order = OSAllocatedUnfairLock(initialState: [Int]())

        let task1 = Task {
            try await clock.sleep(until: .init(offset: .seconds(2)))
            order.withLock { $0.append(1) }
        }

        let task2 = Task {
            try await clock.sleep(until: .init(offset: .seconds(4)))
            order.withLock { $0.append(2) }
        }

        await Task.yield()
        await Task.yield()

        await clock.advance(by: .seconds(5))
        try await task1.value
        try await task2.value
        #expect(order.withLock { $0 } == [1, 2])
    }

    @Test
    func `run processes all pending suspensions`() async throws {
        let clock = Clock.Test()
        let completed = OSAllocatedUnfairLock(initialState: false)

        let task = Task {
            try await clock.sleep(until: .init(offset: .seconds(10)))
            completed.withLock { $0 = true }
        }

        await Task.yield()
        await Task.yield()

        await clock.run()
        try await task.value
        #expect(completed.withLock { $0 })
    }

    @Test
    func `checkSuspension throws when there are active suspensions`() async {
        let clock = Clock.Test()

        let task = Task {
            try await clock.sleep(until: .init(offset: .seconds(100)))
        }

        await Task.yield()
        await Task.yield()

        do {
            try await clock.checkSuspension()
            Issue.record("Expected Suspension.Error")
        } catch {
            // Expected
        }

        task.cancel()
        _ = await task.result
    }

    @Test
    func `advance(by:) composes: two advances sum correctly`() async {
        let clock = Clock.Test()
        await clock.advance(by: .seconds(3))
        await clock.advance(by: .seconds(2))
        #expect(clock.now.offset == .seconds(5))
    }
}
