// Clock.Offset+Carrier.swift
// Clock.Offset conforms to Carrier as a trivial-self-carrier.
//
// All virtual-clock instant types in this package are `Tagged<ClockType, Clock.Offset>`
// (Test.Instant, Immediate.Instant, Unimplemented.Instant). Via the
// parametric `Tagged: Carrier where RawValue: Carrier` extension in
// swift-tagged-primitives, this conformance automatically lifts to
// every Tagged variant, enabling cross-clock generic dispatch:
//
//   func schedule<I: Carrier<Clock.Offset>>(_ instant: I) -> I
//
// accepts Test.Instant, Immediate.Instant, and Unimplemented.Instant
// uniformly.

public import Carrier_Primitives

extension Clock.Offset: Carrier {
    /// Clock.Offset IS its own Underlying.
    public typealias Underlying = Clock.Offset

    // `Domain` defaults to `Never`. `var underlying` and `init(_:)`
    // are inherited from the `Carrier where Underlying == Self`
    // default extension.
}
