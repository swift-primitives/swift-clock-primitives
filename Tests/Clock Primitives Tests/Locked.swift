// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-primitives open source project
//
// Copyright (c) 2024-2026 Coen ten Thije Boonkkamp and the swift-primitives project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

import Synchronization

/// A portable, `Sendable` lock-protected value for tests.
///
/// A cross-platform stand-in for `OSAllocatedUnfairLock` (which lives in Darwin's
/// `os` module and is unavailable on Linux/Windows). It wraps a `~Copyable`
/// `Synchronization.Mutex` in a `final class` so the protected state can be shared
/// by reference across the concurrent `Task.immediate` closures the clock tests use,
/// with the same `withLock { … }` surface as `OSAllocatedUnfairLock`.
final class Locked<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>

    /// Creates a lock holding the given initial value.
    init(initialState: Value) {
        self.mutex = Mutex(initialState)
    }

    /// Runs `body` with exclusive mutable access to the protected value.
    func withLock<Result>(_ body: (inout sending Value) -> sending Result) -> sending Result {
        mutex.withLock(body)
    }
}
