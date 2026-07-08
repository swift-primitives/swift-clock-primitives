import Clock_Primitives
import Testing

extension Clock.Immediate {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Integration {}
        @Suite(.serialized) struct Performance {}
    }
}

// MARK: - Unit

extension Clock.Immediate.Test.Unit {
    @Test
    func `init default now is zero offset`() {
        let clock = Clock.Immediate()
        #expect(clock.now.offset == .zero)
    }

    @Test
    func `init with custom now`() {
        let instant = Clock.Immediate.Instant(offset: .seconds(5))
        let clock = Clock.Immediate(now: instant)
        #expect(clock.now.offset == .seconds(5))
    }

    @Test
    func `minimumResolution defaults to zero`() {
        let clock = Clock.Immediate()
        #expect(clock.minimumResolution == .zero)
    }

    @Test
    func `minimumResolution setter`() {
        let clock = Clock.Immediate()
        clock.minimumResolution = .milliseconds(10)
        #expect(clock.minimumResolution == .milliseconds(10))
    }

    @Test
    func `sleep advances now to deadline`() async throws {
        let clock = Clock.Immediate()
        let deadline = Clock.Immediate.Instant(offset: .seconds(3))
        try await clock.sleep(until: deadline)
        #expect(clock.now == deadline)
    }

    @Test
    func `Instant advanced by duration`() {
        let instant = Clock.Immediate.Instant(offset: .seconds(1))
        let advanced = instant.advanced(by: .seconds(2))
        #expect(advanced.offset == .seconds(3))
    }

    @Test
    func `Instant duration to other`() {
        let a = Clock.Immediate.Instant(offset: .seconds(1))
        let b = Clock.Immediate.Instant(offset: .seconds(4))
        #expect(a.duration(to: b) == .seconds(3))
    }

    @Test
    func `Instant ordering`() {
        let a = Clock.Immediate.Instant(offset: .seconds(1))
        let b = Clock.Immediate.Instant(offset: .seconds(2))
        #expect(a < b)
        #expect(!(b < a))
    }

    @Test
    func `Instant equality`() {
        let a = Clock.Immediate.Instant(offset: .seconds(5))
        let b = Clock.Immediate.Instant(offset: .seconds(5))
        #expect(a == b)
    }

    @Test
    func `Instant hashing: equal values produce equal hashes`() {
        let a = Clock.Immediate.Instant(offset: .seconds(5))
        let b = Clock.Immediate.Instant(offset: .seconds(5))
        #expect(a.hashValue == b.hashValue)
    }
}

// MARK: - Edge Case

extension Clock.Immediate.Test.`Edge Case` {
    @Test
    func `sleep throws when task is cancelled`() async {
        let clock = Clock.Immediate()
        let task = Task {
            try await clock.sleep(until: .init(offset: .seconds(1)))
        }
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
    }

    @Test
    func `Instant advanced by zero`() {
        let instant = Clock.Immediate.Instant(offset: .seconds(1))
        let advanced = instant.advanced(by: .zero)
        #expect(advanced == instant)
    }

    @Test
    func `Instant duration to self is zero`() {
        let instant = Clock.Immediate.Instant(offset: .seconds(3))
        #expect(instant.duration(to: instant) == .zero)
    }

    @Test
    func `Instant default offset is zero`() {
        let instant = Clock.Immediate.Instant()
        #expect(instant.offset == .zero)
    }

    @Test
    func `Instant advanced by negative duration`() {
        let instant = Clock.Immediate.Instant(offset: .seconds(5))
        let advanced = instant.advanced(by: .seconds(-2))
        #expect(advanced.offset == .seconds(3))
    }
}

// MARK: - Integration

extension Clock.Immediate.Test.Integration {
    @Test
    func `sequential sleeps advance time cumulatively`() async throws {
        let clock = Clock.Immediate()
        try await clock.sleep(until: .init(offset: .seconds(1)))
        #expect(clock.now.offset == .seconds(1))

        try await clock.sleep(until: .init(offset: .seconds(5)))
        #expect(clock.now.offset == .seconds(5))
    }
}
