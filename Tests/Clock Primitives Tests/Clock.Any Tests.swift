import Testing
import Clock_Primitives
import os

// Clock.Any is generic — use parallel namespace pattern per [TEST-004]

@Suite("Clock.Any")
struct ClockAnyTests {
    @Suite struct Unit {}
    @Suite struct EdgeCase {}
    @Suite struct Integration {}
    @Suite(.serialized) struct Performance {}
}

// MARK: - Unit

extension ClockAnyTests.Unit {
    @Test
    func `wrapping Immediate clock preserves now`() {
        let immediate = Clock.Immediate()
        let erased = Clock.Any(immediate)
        let erasedNow = erased.now
        _ = erasedNow
    }

    @Test
    func `wrapping Immediate clock preserves minimumResolution`() {
        let immediate = Clock.Immediate()
        immediate.minimumResolution = .milliseconds(10)
        let erased = Clock.Any(immediate)
        #expect(erased.minimumResolution == .milliseconds(10))
    }

    @Test
    func `sleep delegates to wrapped Immediate clock`() async throws {
        let immediate = Clock.Immediate()
        let erased = Clock.Any(immediate)
        let deadline = erased.now.advanced(by: .seconds(3))
        try await erased.sleep(until: deadline)
        #expect(immediate.now.offset == .seconds(3))
    }

    @Test
    func `type-erased instant equality`() {
        let immediate = Clock.Immediate()
        let erased = Clock.Any(immediate)
        let a = erased.now
        let b = erased.now
        #expect(a == b)
    }

    @Test
    func `type-erased instant ordering`() {
        let immediate = Clock.Immediate()
        let erased = Clock.Any(immediate)
        let a = erased.now
        let b = a.advanced(by: .seconds(1))
        #expect(a < b)
        #expect(!(b < a))
    }

    @Test
    func `type-erased instant hashing: equal values produce equal hashes`() {
        let immediate = Clock.Immediate()
        let erased = Clock.Any(immediate)
        let a = erased.now
        let b = erased.now
        #expect(a.hashValue == b.hashValue)
    }

    @Test
    func `type-erased instant duration to other`() {
        let immediate = Clock.Immediate()
        let erased = Clock.Any(immediate)
        let a = erased.now
        let b = a.advanced(by: .seconds(5))
        #expect(a.duration(to: b) == .seconds(5))
    }
}

// MARK: - Edge Case

extension ClockAnyTests.EdgeCase {
    @Test
    func `type-erased instant advanced by zero`() {
        let immediate = Clock.Immediate()
        let erased = Clock.Any(immediate)
        let a = erased.now
        let b = a.advanced(by: .zero)
        #expect(a == b)
    }

    @Test
    func `type-erased instant duration to self is zero`() {
        let immediate = Clock.Immediate()
        let erased = Clock.Any(immediate)
        let a = erased.now
        #expect(a.duration(to: a) == .zero)
    }

    @Test
    func `wrapping Immediate with default minimumResolution is zero`() {
        let immediate = Clock.Immediate()
        let erased = Clock.Any(immediate)
        #expect(erased.minimumResolution == .zero)
    }
}

// MARK: - Integration

extension ClockAnyTests.Integration {
    @Test
    func `wrapping Test clock: sleep and advance`() async throws {
        let test = Clock.Test()
        let erased = Clock.Any(test)
        let resumed = OSAllocatedUnfairLock(initialState: false)

        let task = Task.immediate {
            let deadline = erased.now.advanced(by: .seconds(5))
            try await erased.sleep(until: deadline)
            resumed.withLock { $0 = true }
        }

        test.advance(by: .seconds(5))
        try await task.value
        #expect(resumed.withLock { $0 })
    }

    @Test
    func `sequential sleeps through type-erased Immediate`() async throws {
        let immediate = Clock.Immediate()
        let erased = Clock.Any(immediate)

        let d1 = erased.now.advanced(by: .seconds(1))
        try await erased.sleep(until: d1)
        #expect(immediate.now.offset == .seconds(1))

        let d2 = erased.now.advanced(by: .seconds(2))
        try await erased.sleep(until: d2)
        #expect(immediate.now.offset == .seconds(3))
    }
}
