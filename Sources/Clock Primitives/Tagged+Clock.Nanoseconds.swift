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

extension Tagged where RawValue == Clock.Nanoseconds {
    /// The nanosecond count since boot.
    @inlinable
    public var nanoseconds: UInt64 { rawValue.rawValue }

    /// Creates an instant from a nanosecond count.
    @inlinable
    public init(nanoseconds: UInt64) {
        self.init(__unchecked: (), Clock.Nanoseconds(nanoseconds))
    }
}
