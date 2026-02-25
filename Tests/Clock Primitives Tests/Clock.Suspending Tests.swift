import Testing
import Clock_Primitives

extension Clock.Suspending {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct EdgeCase {}
        @Suite struct Integration {}
        @Suite(.serialized) struct Performance {}
    }
}

// MARK: - Unit

extension Clock.Suspending.Test.Unit {
    @Test
    func `init creates instance`() {
        let clock = Clock.Suspending()
        #expect(clock.minimumResolution == .nanoseconds(1))
    }

    @Test
    func `Instant init stores nanoseconds`() {
        let instant = Clock.Suspending.Instant(nanoseconds: 42)
        #expect(instant.nanoseconds == 42)
    }

    @Test
    func `Instant advanced by positive duration`() {
        let instant = Clock.Suspending.Instant(nanoseconds: 1_000_000_000)
        let advanced = instant.advanced(by: .seconds(2))
        #expect(advanced.nanoseconds == 3_000_000_000)
    }

    @Test
    func `Instant advanced by negative duration`() {
        let instant = Clock.Suspending.Instant(nanoseconds: 3_000_000_000)
        let advanced = instant.advanced(by: .seconds(-1))
        #expect(advanced.nanoseconds == 2_000_000_000)
    }

    @Test
    func `Instant duration to later instant is positive`() {
        let a = Clock.Suspending.Instant(nanoseconds: 1_000_000_000)
        let b = Clock.Suspending.Instant(nanoseconds: 3_000_000_000)
        #expect(a.duration(to: b) == .seconds(2))
    }

    @Test
    func `Instant duration to earlier instant is negative`() {
        let a = Clock.Suspending.Instant(nanoseconds: 3_000_000_000)
        let b = Clock.Suspending.Instant(nanoseconds: 1_000_000_000)
        #expect(a.duration(to: b) == .seconds(-2))
    }

    @Test
    func `Instant ordering`() {
        let a = Clock.Suspending.Instant(nanoseconds: 100)
        let b = Clock.Suspending.Instant(nanoseconds: 200)
        #expect(a < b)
        #expect(!(b < a))
        #expect(!(a < a))
    }

    @Test
    func `Instant equality`() {
        let a = Clock.Suspending.Instant(nanoseconds: 42)
        let b = Clock.Suspending.Instant(nanoseconds: 42)
        let c = Clock.Suspending.Instant(nanoseconds: 43)
        #expect(a == b)
        #expect(a != c)
    }

    @Test
    func `Instant hashing: equal values produce equal hashes`() {
        let a = Clock.Suspending.Instant(nanoseconds: 99)
        let b = Clock.Suspending.Instant(nanoseconds: 99)
        #expect(a.hashValue == b.hashValue)
    }

    @Test
    func `Instant advanced by sub-second duration`() {
        let instant = Clock.Suspending.Instant(nanoseconds: 0)
        let advanced = instant.advanced(by: .milliseconds(500))
        #expect(advanced.nanoseconds == 500_000_000)
    }
}

// MARK: - Edge Case

extension Clock.Suspending.Test.EdgeCase {
    @Test
    func `Instant advanced by zero duration`() {
        let instant = Clock.Suspending.Instant(nanoseconds: 42)
        let advanced = instant.advanced(by: .zero)
        #expect(advanced == instant)
    }

    @Test
    func `Instant duration to self is zero`() {
        let instant = Clock.Suspending.Instant(nanoseconds: 42)
        #expect(instant.duration(to: instant) == .zero)
    }

    @Test
    func `Instant zero nanoseconds`() {
        let instant = Clock.Suspending.Instant(nanoseconds: 0)
        #expect(instant.nanoseconds == 0)
    }

    @Test
    func `Instant wrapping arithmetic on large values`() {
        let instant = Clock.Suspending.Instant(nanoseconds: .max)
        let advanced = instant.advanced(by: .nanoseconds(1))
        #expect(advanced.nanoseconds == 0)
    }

    @Test
    func `Instant round-trip: advance then measure duration`() {
        let start = Clock.Suspending.Instant(nanoseconds: 1000)
        let duration: Duration = .milliseconds(250)
        let end = start.advanced(by: duration)
        #expect(start.duration(to: end) == duration)
    }
}
