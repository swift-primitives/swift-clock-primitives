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

extension Tagged where Underlying == Clock.Nanoseconds {
    /// The nanosecond count since boot.
    @inlinable
    public var nanoseconds: UInt64 { underlying.rawValue }

    /// Creates an instant from a nanosecond count.
    @inlinable
    public init(nanoseconds: UInt64) {
        self.init(Clock.Nanoseconds(nanoseconds))
    }
}
