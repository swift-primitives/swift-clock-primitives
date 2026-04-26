// Clock.Nanoseconds+Carrier.swift
// Clock.Nanoseconds conforms to Carrier as a trivial-self-carrier.
//
// All clock-instant types in this package are `Tagged<ClockType, Clock.Nanoseconds>`
// (Continuous.Instant, Suspending.Instant). Via the parametric
// `Tagged: Carrier where RawValue: Carrier` extension in
// swift-tagged-primitives, this conformance automatically lifts to
// every Tagged variant — `Continuous.Instant: Carrier<Clock.Nanoseconds>`,
// `Suspending.Instant: Carrier<Clock.Nanoseconds>` — enabling
// cross-clock generic dispatch:
//
//   func deadline<I: Carrier<Clock.Nanoseconds>>(_ instant: I) -> I
//
// accepts both Continuous.Instant and Suspending.Instant uniformly.

public import Carrier_Primitives

extension Clock.Nanoseconds: Carrier {
    /// Clock.Nanoseconds IS its own Underlying.
    public typealias Underlying = Clock.Nanoseconds

    // `Domain` defaults to `Never`. `var underlying` and `init(_:)`
    // are inherited from the `Carrier where Underlying == Self`
    // default extension.
}
