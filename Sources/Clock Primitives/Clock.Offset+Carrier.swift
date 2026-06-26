// Clock.Offset+Carrier.swift
// Clock.Offset conforms to Carrier.`Protocol` as a trivial-self-carrier.
//
// All virtual-clock instant types in this package are `Tagged<ClockType, Clock.Offset>`
// (Test.Instant, Immediate.Instant, Unimplemented.Instant). Via the
// parametric `Tagged: Carrier.`Protocol` where Underlying: Carrier.`Protocol``
// extension in swift-tagged-primitives, this conformance automatically lifts to
// every Tagged variant, enabling cross-clock generic dispatch:
//
//   func schedule<I: Carrier.`Protocol`>(_ instant: I) -> I where I.Underlying == Clock.Offset
//
// accepts Test.Instant, Immediate.Instant, and Unimplemented.Instant
// uniformly.

public import Carrier_Primitives

extension Clock.Offset: Carrier.`Protocol` {
    /// Clock.Offset IS its own Underlying.
    public typealias Underlying = Clock.Offset

    // `Domain` defaults to `Never`. `var underlying` and `init(_:)`
    // are inherited from the `Carrier where Underlying == Self`
    // default extension.
}
