# Paying for a resource

Ask an HTTP server for something, find out it costs money, and pay for it --
either from the app's own key, or by asking the owner.

## Overview

Some servers answer a request with `402 Payment Required` and a machine-readable
demand: pay this much of this token to this address, then ask again. ``PaygentAgent``
turns that exchange into one call, `agentPay(call:)`, and reports what happened
as a ``PayResult``.

Read the result before reading anything else in this article. Every case is an
answer you have to handle, and two of them mean money moved.

### One call

```swift
import PaygentSdk
import PaygentMobileCore

let agent = try PaygentAgent(
    configJson: #"{"rpcBase": "https://rpc.paygent.net"}"#,
    // The signing key and the stored wallet record. The optional
    // `history:`, `pocket:` and `escalation:` hosts are left out here, so
    // the operations they serve refuse.
    host: signer,
    session: walletStore
)

let call = PayCall(
    method: "GET",
    url: "https://api.example.com/reports/2026-09",
    headers: [:],
    bodyBase64: nil,
    wallet: nil,
    // The ceiling, in the quoted token's base units. A demand above it is
    // refused before anything is signed. `nil` means unbounded, which is
    // rarely what you want.
    maxAmount: "250000",
    maxSats: nil,
    token: nil
)

let result = try await agent.agentPay(call: call)
```

### Every answer

```swift
switch result {
case .served(let response):
    // The server asked for nothing. This is the ordinary case for a free
    // resource, and it is also what a paid resource looks like once your
    // credential is cached by the server.
    handle(response)

case .paidAndServed(let rail, _, let settlement, let response):
    // Money moved and the resource arrived. `settlement` is the receipt; it is
    // the only record of this spend, so store it before you do anything else.
    record(rail: rail, settlement: settlement)
    handle(response)

case .paidNotServed(let rail, _, let settlement, let response):
    // Money moved and the resource did NOT arrive. There is no refund path on
    // these rails. This is a result, not a thrown error, precisely so that a
    // caller cannot miss it by only writing a `catch`.
    record(rail: rail, settlement: settlement)
    reportUnrecoverableSpend(response)

case .rejected(let rail, _, let response):
    // The server refused and nothing was paid. The only case that promises a
    // payment was attempted and no money moved.
    reportRefusal(rail: rail, response)

case .ownerApprovalNeeded(let rail):
    // The demand is beyond what this app may pay on its own. Nothing was paid.
    // See "Escalating over the mandate" below.
    try await escalate(rail: rail)

case .pocketTopUpNeeded(_, _, let amountSats):
    // A Lightning invoice larger than the app's own pocket. The owner tops the
    // pocket up -- they are never asked to pay the merchant -- and the call is
    // made again.
    try await askOwnerToTopUp(sats: amountSats)
}
```

A `throw` from `agentPay(call:)` almost always means the attempt could not be
made and is safe to retry. Almost: a `200` that arrives carrying a
settlement receipt is refused rather than reported as free, because money moved
that the call cannot account for, and the receipt travels out in the message. Log
the message text, not a category.

### What this binding pays today

`agentPay(call:)` on iOS fetches the resource, reads the demand, and, when the
demand is x402 and your ``AgentHost`` signs with the device's hardware key, pays
it from the wallet's on-chain executor module -- silently, inside the spending
limit the owner set on chain. The result is `paidAndServed` with `rail: "x402"`.

Two things make it stop and hand the demand to the owner instead, both reported
as `ownerApprovalNeeded` rather than thrown: a host whose key is not device
hardware (a software or relay-only key never signs a payment on its own), and a
demand the wallet cannot settle from its module -- over the limit, a chain it is
not deployed on, or a token it does not hold. Either way the next section is the
code that finishes the payment.

A demand on a rail this binding does not speak (MPP, Lightning) is refused by
name, as a thrown ``MobileError``: reporting an unwired protocol as "your owner
can approve this" would send a person to approve a payment on a rail nothing here
speaks.

## Escalating over the mandate

The owner approves a payment by signing it on their own device. Your app never
sees their key; it hands over a description of the payment and gets back a
signature.

```swift
let authorization = try await agent.agentEscalateX402Authorization(
    request: X402EscalationRequest(
        chainId: 8453,
        network: "base",
        safeAddress: wallet.address,
        payTo: demand.payTo,
        amount: demand.maxAmountRequired,
        asset: demand.asset,
        maxTimeoutSeconds: 60,
        eip712Name: demand.extra.name,
        eip712Version: demand.extra.version,
        resourceUrl: call.url,
        // Shown to the owner. This is the sentence a person reads before
        // approving a payment, so write it for them: what they are buying, not
        // which endpoint you called.
        resourceDescription: "September usage report"
    )
)
```

Two things about this call worth knowing before you build around it.

It takes as long as a person takes. The owner's phone may be face-down on a
table. Treat it as an operation with no useful timeout rather than a network
call, and keep the app usable while it is outstanding.

And your app fills the request in from the server's own `402`. Every field above
is copied from the demand -- `payTo`, `amount`, `asset`, and the EIP-712 `name`
and `version` from its `extra` -- because that is what the owner is asked to
approve. Sending them anything else is asking them to sign a different payment
than the one the server demanded.

What comes back is an ``Eip3009Authorization``: the owner's signature over that
payment. Put it in the `X-PAYMENT` header the server named and send the request
again.

## Amounts never cross as numbers

Every amount in this SDK is a string, and that is not an oversight. A token
balance can carry 18 decimal places; no floating-point type in Swift can hold
one without rounding it, and rounding a balance is how money goes missing.

``Amount`` converts between the two forms a server and a person each use:

```swift
// A person types "1.5"; USDC has 6 decimals; the wire wants base units.
let baseUnits = try Amount.toBaseUnits(input: "1.5", decimals: 6)  // "1500000"

// And back, for display.
let shown = try Amount.fromBaseUnits(
    raw: balance.amount, decimals: 6, maxFractionDigits: 2
)
```

A fraction finer than the token can represent is refused rather than rounded
away.
