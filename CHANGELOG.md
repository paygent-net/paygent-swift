# Changelog

Versions of the public Swift package. The contract is the operation set in
`capabilities.toml`, so every entry says which operations moved.

A release is refused when this file has no section for the version being cut,
which is why an entry exists before the tag does.

## 0.2.0

Enrollment (RFC-0065 S5), the half an attached app can use today. One
operation joins the agent tier:

| operation | what it does |
|---|---|
| `agent.mandate` | what this agent may spend on a wallet, read from the chain: its module, whether it is deployed and enabled, and the limit held by the guard the Safe enforces |

It comes back as a record, `AgentMandate`, generated from the one Rust
definition the browser binding also carries. Nothing in it is taken from the
owner's reply and nothing is cached: the module is derived from the host's own
key, the guard is read out of the Safe's storage, and a read that fails throws
-- it never reports "not attached" or a limit of zero for a chain it could not
reach.

The constructor gains nothing; `agent.mandate` reads through the same
`chainRpc` / `rpcBase` the config already names.

Asking to be attached is not on this release. The request has to travel to the
owner's device, and this binding does not yet carry it; the operation lands
with the release that does, rather than as a name that refuses every call.

## 0.1.0

First public release. The agent tier, as 14 operations:

| operation | what it does |
|---|---|
| `agent.session` | what is known about the wallet this client acts for |
| `agent.networks` | the chains it supports, and whether the wallet is deployed on each |
| `agent.balances` | token balances |
| `agent.transactions` | recent transactions |
| `agent.authorize` | whether an intent may be paid silently or has to reach the owner |
| `agent.intent` | a parked operation, by id |
| `agent.await_intent` | block until a parked operation is decided |
| `agent.deploy_wallet` | deploy the wallet on one chain |
| `agent.transfer` | move tokens |
| `agent.solana_pocket` | the agent's Solana spend account |
| `agent.refill_solana_pocket` | top that account up from the treasury |
| `agent.sweep_solana_pocket` | return what is left of it |
| `agent.escalate_x402_authorization` | put an x402 payment in front of the owner and get back what they signed |
| `agent.pay` | fetch a resource, and pay for it if the server asks |

Nothing is removed or deprecated: there is no previous version.

Known limits: `agent.pay` settles x402 demands from the app's own key when the
host signs with device hardware, inside the wallet's on-chain limit; a software or
relay-only key, or a demand the wallet cannot settle from its module, is reported
as needing the owner rather than paid. MPP and Lightning demands are refused by
name on this binding. The documentation catalogue's *Paying for a resource*
article walks through both the silent path and the hand-off.
