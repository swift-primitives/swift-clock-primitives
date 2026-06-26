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

extension Tagged where Underlying == Clock.Offset {
    /// The duration offset from zero.
    @inlinable
    public var offset: Swift.Duration { underlying.rawValue }

    /// Creates an instant from a duration offset.
    @inlinable
    public init(offset: Swift.Duration = .zero) {
        self.init(Clock.Offset(offset))
    }
}
