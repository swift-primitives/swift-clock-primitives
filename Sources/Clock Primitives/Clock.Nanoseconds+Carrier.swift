// Clock.Nanoseconds+Carrier.swift
// Clock.Nanoseconds conforms to Carrier.`Protocol` as a trivial-self-carrier.
//
// All clock-instant types in this package are `Tagged<ClockType, Clock.Nanoseconds>`
// (Continuous.Instant, Suspending.Instant). Via the parametric
// `Tagged: Carrier.`Protocol` where Underlying: Carrier.`Protocol`` extension in
// swift-tagged-primitives, this conformance automatically lifts to every Tagged
// variant — `Continuous.Instant` and `Suspending.Instant` both carry
// `Clock.Nanoseconds` as their Underlying — enabling cross-clock generic dispatch:
//
//   func deadline<I: Carrier.`Protocol`>(_ instant: I) -> I where I.Underlying == Clock.Nanoseconds
//
// accepts both Continuous.Instant and Suspending.Instant uniformly.

public import Carrier_Primitives

extension Clock.Nanoseconds: Carrier.`Protocol` {
    /// Clock.Nanoseconds IS its own Underlying.
    public typealias Underlying = Clock.Nanoseconds

    // `Domain` defaults to `Never`. `var underlying` and `init(_:)`
    // are inherited from the `Carrier where Underlying == Self`
    // default extension.
}
