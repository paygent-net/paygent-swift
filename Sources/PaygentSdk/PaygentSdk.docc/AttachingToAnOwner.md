# Attaching to an owner

Find the person your app will work for, ask them for a spending limit, and
keep a line open so a payment over that limit can go to them.

## Overview

A new app has a key and nothing to spend. Before ``PaygentAgent`` can pay for
anything, an owner has to do three things on their own phone: recognise your
app, attach it to one of their wallets, and set how much it may spend. Later,
when a payment is larger than that, the same owner is the one who approves it.

All of that travels through a relay as sealed messages the relay cannot read.
This SDK holds both ends of the conversation that are yours -- the encryption,
the relay protocol, and checking every answer -- so your app does four things:

1. Open a pairing and show the owner a QR code.
2. Store the record the SDK hands you, in the keychain.
3. Ask to be attached, and wait for the answer.
4. Pass the link to ``PaygentAgent`` as its escalation host.

Do them in that order. Each step needs the one before it.

### Pair with the owner

```swift
import PaygentSdk

let host = try SecureEnclaveAgentHost.make(account: "agent")

let pairing = try await agentStartOwnerPairing(
    host: host,
    relayUrl: "wss://relay.paygent.net",
    // What the owner's approval screen calls your app, and this machine.
    agentName: "Virgil",
    hostName: Host.current().localizedName
)

// Show this as a QR code. The owner scans it with the Paygent app.
showQRCode(pairing.qrUrl())

// Returns once the owner has approved on their phone, and every grant they
// sent has been checked against their passkey.
let link = try await pairing.complete(store: keychainStore)
```

Pairing refuses a host whose `signerBacking()` does not declare a hardware
key, and it refuses before anything is sent. The identity the owner pairs with
*is* that key; a key that may be a copy on disk is not paired at all.

`complete(store:)` waits as long as the pairing is open (`expiresAtMs()`), and
throws if the owner never answers. Call `cancel()` if the person closes the
window first.

### Keep the record

`OwnerLinkStore` is the one callback this part of the SDK needs. It is handed
an opaque string and stores it:

```swift
final class KeychainOwnerLinkStore: OwnerLinkStore {
    func saveOwnerLink(recordJson: String) throws {
        try keychain.set(recordJson, forKey: "paygent.owner-link")
    }
}
```

Put it in the keychain and nowhere else. The record holds the secret your app
shares with the owner's phone and the key that speaks for it at the relay.

The SDK saves the record when pairing completes, before it returns the link,
and again whenever it changes -- when the owner attaches your app to a wallet,
and when they renew its permission to write to them. A save that throws during
`complete(store:)` or `awaitAttachment` fails that call, because a link or a
wallet that does not survive a restart would be stranded; a failed save of a
renewed permission is logged and retried on the next renewal.

On the next launch, reconnect from what you stored:

```swift
let link = try await ownerLinkRestore(
    recordJson: try keychain.get("paygent.owner-link"),
    host: host,
    store: keychainStore
)
```

The record is checked again before anything connects. A record made by a
different signing key, or whose grants no longer verify, is refused.

### Ask to be attached

```swift
let requestId = try await link.requestAttachment(input: AttachmentRequestInput(
    ownerDid: link.ownerDid(),
    chainId: 8453,
    token: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",  // USDC on Base
    amountHex: "0x989680",                                // 10 USDC
    periodSeconds: 86_400,                                // per day
    label: "Virgil",
    requestId: UUID().uuidString,
    issuedAtMs: nowMs,
    expiresAtMs: nowMs + 10 * 60 * 1000
))

switch try await link.awaitAttachment(
    requestId: requestId,
    chainId: 8453,
    // A JSON-RPC endpoint on that chain. The wallet address in the owner's
    // answer is recomputed here from their passkey, never believed.
    rpcUrl: "https://mainnet.base.org",
    timeoutSecs: 600
) {
case .granted(let attachment):
    // Verified: the owner's signature, the wallet address, and the module
    // your own key derives. Store these in the record your
    // AgentSessionHost serves.
    saveWallet(
        address: attachment.walletAddress(),
        chainId: attachment.chainId(),
        index: attachment.walletIndex(),
        executorModule: attachment.executorModule()
    )
case .rejected(let reason, let chainId, let token, let message):
    // `message` says what happened and what to do, in plain English: show
    // it as is. Branch on `reason` when your app can act by itself.
    switch reason {
    case .walletNotDeployed:
        // The owner's account exists but has no deposit on this network
        // yet. Ask again once they have added money to it there.
        waitForOwnerDeposit(chainId: chainId, message: message)
    case .unsupportedToken:
        // Only USDC allowances can be granted. `token` is what you asked for.
        askAgainInUsdc(chainId: chainId, rejectedToken: token)
    default:
        showDeclined(message)
    }
}
```

Only `.declined` is the owner's own choice. Every other reason is decided by the
owner's app without showing them the request: a network it does not support
(`.unsupportedChain`), a token other than that network's USDC
(`.unsupportedToken`), no account at all (`.noWallet`), an account with no
deposit on that network yet (`.walletNotDeployed`), or a request it could not
read (`.invalidRequest`). `.expired` means nobody answered in time.

The amount you ask for is a request. What your app may actually spend is what
the owner set on chain, which `agentMandate` reads; it is never taken from the
answer.

`awaitAttachment` throws ``MobileError`` `.InvalidInput` for an answer that
does not verify -- it is never stored -- and `.Rpc` when nothing arrives in time
or the chain could not be read to check the address. Only the second is worth
calling again.

### Hand the owner the payments over your limit

```swift
let agent = try PaygentAgent(
    configJson: #"{"chainRpc": {"8453": "https://mainnet.base.org"}}"#,
    host: host,
    session: walletStore,
    escalation: link.escalationHost()
)
```

From here, when `agentPay(call:)` returns `ownerApprovalNeeded`, the
escalation described in <doc:PayingForAResource> goes to this owner through
the same line: the payment is sealed for their phone, they approve it there,
and the signed ``Eip3009Authorization`` comes back. Your app writes none of
the transport.

Keep `link` alive for as long as the agent may escalate. It holds one relay
connection and reconnects on its own; releasing the last reference closes it.

### What still depends on Paygent

The relay carries these messages. If it is unreachable, pairing and escalation
wait, and in-limit payments do not: your app signs those itself, against the
chain, with no Paygent server in the path.
