import Clock_Primitives
import Testing

extension Clock.Unimplemented {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Integration {}
        @Suite(.serialized) struct Performance {}
    }
}

// MARK: - Unit

extension Clock.Unimplemented.Test.Unit {
    @Test
    func `init creates instance`() {
        let clock = Clock.Unimplemented()
        _ = clock
    }

    @Test
    func `now returns zero instant`() {
        let clock = Clock.Unimplemented()
        #expect(clock.now.offset == .zero)
    }

    @Test
    func `minimumResolution is zero`() {
        let clock = Clock.Unimplemented()
        #expect(clock.minimumResolution == .zero)
    }

    @Test
    func `Instant advanced by duration`() {
        let instant = Clock.Unimplemented.Instant(offset: .seconds(1))
        let advanced = instant.advanced(by: .seconds(2))
        #expect(advanced.offset == .seconds(3))
    }

    @Test
    func `Instant duration to other`() {
        let a = Clock.Unimplemented.Instant(offset: .seconds(1))
        let b = Clock.Unimplemented.Instant(offset: .seconds(4))
        #expect(a.duration(to: b) == .seconds(3))
    }

    @Test
    func `Instant ordering`() {
        let a = Clock.Unimplemented.Instant(offset: .seconds(1))
        let b = Clock.Unimplemented.Instant(offset: .seconds(2))
        #expect(a < b)
        #expect(!(b < a))
    }

    @Test
    func `Instant equality`() {
        let a = Clock.Unimplemented.Instant(offset: .seconds(5))
        let b = Clock.Unimplemented.Instant(offset: .seconds(5))
        #expect(a == b)
    }

    @Test
    func `Instant hashing: equal values produce equal hashes`() {
        let a = Clock.Unimplemented.Instant(offset: .seconds(5))
        let b = Clock.Unimplemented.Instant(offset: .seconds(5))
        #expect(a.hashValue == b.hashValue)
    }
}

// MARK: - Edge Case

extension Clock.Unimplemented.Test.`Edge Case` {
    @Test
    func `Instant advanced by zero`() {
        let instant = Clock.Unimplemented.Instant(offset: .seconds(1))
        let advanced = instant.advanced(by: .zero)
        #expect(advanced == instant)
    }

    @Test
    func `Instant duration to self is zero`() {
        let instant = Clock.Unimplemented.Instant(offset: .seconds(3))
        #expect(instant.duration(to: instant) == .zero)
    }

    @Test
    func `Instant default offset is zero`() {
        let instant = Clock.Unimplemented.Instant()
        #expect(instant.offset == .zero)
    }

    @Test
    func `now always returns fresh zero instant`() {
        let clock = Clock.Unimplemented()
        let a = clock.now
        let b = clock.now
        #expect(a == b)
        #expect(a.offset == .zero)
    }
}
