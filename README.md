# Paygent SDK for Swift

Let an app spend money on its own, inside a limit its owner set on-chain, and
hand anything larger back to the owner to approve.

The app holds a key that can sign small payments. The owner holds a separate
key -- on their phone, in a Secure Enclave -- that can do everything else. What
"small" means is not a setting in this package: it is a spending limit recorded
in a contract the owner controls, so an app that is completely compromised
still cannot spend past it.

This package is generated: nothing in this repository is edited by hand. Report
a problem or ask for a change by opening an issue here.

## Requirements

iOS 16 or later. Xcode 15.4 or later (the manifest is `swift-tools-version:5.10`).

There is no macOS or Mac Catalyst build: the binary carries an iOS device slice
and two iOS simulator slices only.

## Adding it

In Xcode: **File > Add Package Dependencies...**, paste
`https://github.com/paygent-net/paygent-swift`, and set the dependency rule to **Up to Next Minor
Version** from `0.7.0`.

From another package:

```swift
// Package.swift
dependencies: [
    .package(
        url: "https://github.com/paygent-net/paygent-swift.git",
        .upToNextMinor(from: "0.7.0")
    ),
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "PaygentSdk", package: "paygent-swift"),
        ]
    ),
]
```

**Use `.upToNextMinor`, not `from:`, while this package is on `0.x`.** SwiftPM's
`from:` means "up to the next major", and for `0.1.0` the next major is `1.0.0` --
so `from:` would accept every `0.x` release, including the ones that break your
build. Before `1.0.0` a breaking change lands in the **minor**; see
[Versioning](#versioning).

Resolution downloads a ~230 MB binary once and caches it.

## Using it

Your app supplies two things it cannot delegate: an `AgentHost`, which is the
key that signs, and an `AgentSessionHost`, which is the wallet record the app
stored when its owner hired it. Three more hosts are optional -- an
`AgentHistoryHost` for transaction history, an `AgentPocketHost` for the Solana
pocket, and an `AgentEscalationHost` for reaching the owner -- and each one you
leave out makes the operations it serves refuse rather than quietly do
something else. The SDK supplies the payment logic.

```swift
import PaygentSdk
import PaygentMobileCore

let agent = try PaygentAgent(
    // `rpcBase` is any Ethereum JSON-RPC endpoint. Paygent runs one as a
    // convenience; nothing here requires it, and pointing this at your own
    // node or a public provider changes nothing else.
    configJson: #"{"rpcBase": "https://rpc.paygent.net"}"#,
    host: MySigner(),
    session: MyWalletStore()
)

let result = try await agent.agentPay(
    call: PayCall(
        method: "GET",
        url: "https://api.example.com/report",
        headers: [:],
        bodyBase64: nil,
        wallet: nil,
        maxAmount: "250000",   // 0.25 USDC, in the token's base units
        maxSats: nil,
        token: nil
    )
)
```

`PayResult` is a closed set of answers and every one of them has to be handled.
`paidNotServed` in particular is a *result*, not a thrown error: the money is
gone and the resource did not arrive. A caller that only inspects `catch` will
miss it.

The full walkthrough -- including what to do with `ownerApprovalNeeded` -- is in
the documentation catalogue: in Xcode, **Product > Build Documentation**, then
open *PaygentSdk > Paying for a resource*. The same code is in
[`examples/`](examples).

## What is in the package

| product | surface | for |
|---|---|---|
| `PaygentSdk` | the agent tier: `PaygentAgent`, the `AgentHost` you implement, and the records those operations exchange | an app that spends inside a mandate its owner granted |
| `PaygentMobileCore` | everything the underlying library exports, owner-tier wallet administration included | the owner's own authorizer app |

`PaygentSdk` is a curated view of the same one binary, not a second build. It
narrows what you are *offered*, not what your app *ships*: both products link
the same binary and neither is smaller. Import `PaygentSdk` and you see the
agent tier; nothing stops you importing `PaygentMobileCore` and seeing the rest,
and there is no support promise on what you find there.

## Versioning

The stable contract is the **operation set**, not the generated Swift surface.
The generated bindings export several hundred functions and could never be held
stable; the operations can be, and they are listed for each version in
[CHANGELOG.md](CHANGELOG.md). That list is held to the operation set by tests
upstream: every operation the changelog names must be one the binding exports,
and every agent-tier operation that arrives in a version must be named in that
version's section, so a release whose changelog and binding disagree is not cut.

* The git tags on this repository are this package's versions, and nothing else
  is. They do not track the internal release train the binary is built from and
  never will: an internal refactor must not spend an external major.
* On `0.x`: a breaking change to the operation set bumps the **minor**; anything
  else bumps the patch. Pin with `.upToNextMinor`.
* From `1.0.0`: ordinary semver. One previous major stays supported for six
  months after its successor ships.
* Removing or renaming an operation is announced in [CHANGELOG.md](CHANGELOG.md)
  one minor (on `0.x`) or one major (from `1.0.0`) before it happens.

## Licence

[Business Source License 1.1](LICENSE), with Paygent's Additional Use Grant.
In short: use it and ship it unmodified, commercially or not, for free; modify
it for your own personal use, or to contribute the change back; anything else
needs a commercial licence; and each version becomes Apache-2.0 four years
after it is published. [LICENSE-FAQ.md](LICENSE-FAQ.md) answers the common
questions in plain language; if it and the licence disagree, the licence wins.
Your app stays yours: linking this package does not put it under any licence.

Releases 0.1.0, 0.2.0 and 0.3.0 were published under the Mozilla Public
License 2.0 and remain under it.

The binary links third-party code under MIT, BSD-3-Clause, ISC, Apache-2.0,
MPL-2.0 and CC0; every notice is in
[THIRD-PARTY-NOTICES.txt](THIRD-PARTY-NOTICES.txt).

### Getting the source of the binary

The `.xcframework` this package downloads is compiled from
[paygent-net/rust-common](https://github.com/paygent-net/rust-common). For the
three MPL-era releases, the section 3.2 offer stands: open an issue on this
repository naming the version you have, and the Source Form of the MPL-covered
files that went into it is sent to you at no charge.
