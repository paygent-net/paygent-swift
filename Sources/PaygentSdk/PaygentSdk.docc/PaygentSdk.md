# ``PaygentSdk``

Let an app spend money on its own, inside a limit its owner set, and hand
anything larger back to the owner.

## Overview

Two parties, two keys.

The **owner** is a person. They hold a key on their own phone, in hardware they
alone can unlock, and it can do everything: deploy the wallet, move the whole
balance, change who may spend and how much.

The **agent** is your app. It holds a different key, and what that key may do is
written into a contract on a public blockchain -- an amount, and a period. That
limit is not a setting in this package and your app cannot raise it. An app that
is completely taken over still cannot spend past what its owner allowed, because
nothing in the app is what enforces it.

This SDK is the agent's side of that arrangement. Every operation here either
stays inside the limit, or stops and asks the owner.

### What you supply

The SDK does not open a keychain, a database or a socket of its own. It calls
back into your app to get the things it cannot have. That is what makes the
payment logic testable and the same on every platform.

Two of those callbacks are required. ``AgentHost`` is the signing key, and
``AgentSessionHost`` is the wallet record your app stored when its owner hired
it -- without one there is no wallet to act for. Three are optional, and leaving
one out is a decision rather than an omission: without an ``AgentHistoryHost``
`agentTransactions` refuses, without an ``AgentPocketHost`` the three Solana
pocket operations refuse, and without an ``AgentEscalationHost`` an x402
escalation refuses by name rather than being signed locally.

Balances and networks are not among them. The SDK reads both itself, from the
endpoint your configuration names.

One member has no default on purpose. ``AgentHost`` requires
`signerBacking()`, where your app states what holds its signing key -- a Secure
Enclave, or nothing. Declaring hardware is what unlocks the silent path. An app
that does not say is treated as having no key of its own, and every payment goes
to the owner. It fails towards asking a human, never towards spending.

## Topics

### Getting started

- <doc:PayingForAResource>

### The client

- ``PaygentAgent``
- ``PaygentAgentProtocol``
- ``AgentSignerBacking``
- ``AgentHardwareKind``

### What your app supplies

- ``AgentHost``
- ``AgentSessionHost``
- ``AgentHistoryHost``
- ``AgentPocketHost``
- ``AgentEscalationHost``

### Paying for a resource

- ``PayCall``
- ``PayResult``
- ``PayResponse``
- ``PaySettlement``
- ``X402EscalationRequest``
- ``Eip3009Authorization``

### The spend decision

- ``PolicyIntent``
- ``IntentAmount``
- ``PolicyDecision``
- ``PolicyAction``
- ``SigningPath``
- ``AuthLevel``
- ``CommandContext``
- ``Surface``
- ``SigningCapability``
- ``HardwareKind``

### Wallet state

- ``SessionSnapshot``
- ``OwnerSummary``
- ``ChainDeploymentSummary``
- ``SolanaWalletSummary``
- ``TokenBalance``
- ``TransactionSummary``

### Moving money

- ``DeployUserOpRequest``
- ``TransferUserOpRequest``
- ``SolanaPocketInfo``
- ``SolanaPocketReceipt``
- ``Period``
- ``UserOpHash``

### Amounts

- ``Amount``

### Errors

- ``MobileError``
- ``AgentHostError``
