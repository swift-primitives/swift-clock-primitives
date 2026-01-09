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

/// Namespace for clock types.
///
/// Clocks provide a way to measure the passage of time and schedule work.
/// This namespace contains both real clocks (Continuous, Suspending) and
/// test clocks (Test, Immediate, Unimplemented).
public enum Clock {}
