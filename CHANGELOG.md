# Changelog

Versions of the public Swift package. The contract is the operation set in
`capabilities.toml`, so every entry says which operations moved.

A release is refused when this file has no section for the version being cut,
which is why an entry exists before the tag does.

Licence: every release after 0.3.0 is under the Business Source License 1.1
(`LICENSE` and `LICENSE-FAQ.md` in the package). 0.1.0, 0.2.0 and 0.3.0 were
published under the Mozilla Public License 2.0 and remain under it.

## 0.5.0

### Asking for a different allowance, and hearing it changed

Two operations join the agent tier:

| operation | what it does |
|---|---|
| `agent.request_allowance` | sign an `agent.allowance-request` ("wants $X a day") with this device's hardware key, for the host to seal into the owner's invite mailbox |
| `agent.apply_mandate_changed` | act on the owner's `agent.mandate-changed` notice by forgetting the cached limit it names, so the next payment reads the new limit from the chain |

`agent.request_allowance` takes an `AllowanceRequestInput` record and returns the request body as
JSON, for the same reason `agent.request_attachment` does: those bytes are what
the hardware signature covers. It refuses a host with no hardware-backed key,
a zero ceiling, and a lifetime outside the bounds the owner's device applies.

### Constructors for the untrusted records

`UntrustedText` and `WebOrigin` arrived in 0.4.0 with no way to build them but
the generated field-by-field initializer, which checks nothing. This release
adds the constructors that do:

| call | behaviour |
|---|---|
| `Untrusted.parse(_:)` | computes `display` and the three flags from the text itself; never fails |
| `Untrusted.parseOptional(_:)` | the same, and `nil` for text that sanitises to nothing |
| `Untrusted.webOrigin(_:)` | a strict origin, and it **throws rather than trimming**: a resource URL is not an origin |

Use them. The initializer is still reachable and still forwards whatever it is
given, so a `display` an app fills in itself is the string the owner reads.

## 0.4.0

Five changes that have nothing to do with each other: an agent can ask to be
attached and read the owner's answer, what an agent says stops being the same
kind of value as what the wallet derived, the policy engine can be told who a
payment pays, a payment can be named and the name asked about afterwards, and a
failed payment says whether the money may already have moved. The package also
ships a Secure Enclave implementation of the `AgentHost` signing callbacks,
which changes no operation at all. Between them seven operations change
signature and three join the agent tier, so a host pinned to 0.3.0 does not
compile against this release.

### Asking to be attached

Two operations join the agent tier, and with them an app can enroll itself end
to end:

| operation | what it does |
|---|---|
| `agent.request_attachment` | sign an `agent.attachment-request` with this device's hardware key, for the host to seal into the owner's invite mailbox |
| `agent.verify_attachment_granted` | verify the owner's reply and, only if it holds, hand back the attachment |

`agent.request_attachment` takes an `AttachmentRequestInput` record --
generated from the one Rust definition -- and returns the request body as JSON, because those bytes are what the hardware
signature covers and a record re-serialized by a host is not reliably the same
bytes. It names no asker: the identity is read off the signing key, so the only
`delegateDid` it can produce is the one that key derives. A host that reports
no hardware-backed key is REFUSED here rather than signed for with a software
key. Note what that rests on: the report is the host's own, through
`signerBacking()`, so this is the binding declining to downgrade rather than a
check on what the device really holds. A host that misreports its backing
gets a request signed by whatever key it handed over.

`agent.verify_attachment_granted` returns `VerifiedAttachment`, an opaque
object with no initializer. Holding one is the proof that the reply was
checked: the relay grant's signature against the paired owner's passkey, the
wallet address recomputed from that passkey at the carried index, the executor
module this device's own key derives, and the request and chain this device
actually asked for. Read `requestId`, `walletAddress`, `chainId`,
`walletIndex`, `ownerDid`, `executorModule` and `delegationJson` off it.

The mandate is deliberately not among those fields. What the agent may spend is
`agent.mandate`, read off the guard the Safe enforces, so what the owner
actually set binds rather than what the reply said.

### Text somebody else wrote

Five operations change signature, and one host callback changes the JSON it is
handed WITHOUT changing signature.

**`UntrustedText`.** Five strings on an approval surface become `UntrustedText`
instead of `String`: the summary's `contextNote`, plus
`solanaEscalateRefill.resourceUrl`, `solanaEscalateRefill.resourceDescription`,
`lightningEscalateRefill.resourceDescription` and
`mppCharge.resourceDescription`. Strings somebody else wrote that stay
`String`s keep none of the protection below. Two of them stay that way on
purpose: `mppCharge.resourceUrl` (see the section on it for why, and for what
that costs) and `mppCharge.challengeHeader`, which is the server's challenge
byte for byte because it is echoed back inside the credential -- protocol
material, not label material. `mppCharge.payTo` and `mppCharge.currency` stay
`String`s and are genuinely DERIVED: as of this release the charge validation
parses both as addresses before anybody is asked to approve anything, so a
challenge naming something that is not an address is refused rather than shown,
and what reaches the screen is the EIP-55 checksummed spelling -- the same
mixed-case form a block explorer shows, whatever casing the server sent. They
are the bytes the transaction will carry, not a second reading of the server's
text, because the builder calls the same parse.

`UntrustedText` carries `raw` (exactly what arrived), `display` (the same text
with characters that render as nothing or change reading direction removed, runs
of whitespace collapsed, capped at 200 characters), `hiddenRemoved` (the
arriving text contained such characters),
`whitespaceNormalised` (only spacing was tidied) and `truncated`. There is no
field to drop straight into a label without first choosing between `raw` and
`display`, which is the point: an owner approving a payment should never see a
string an injected model chose rendered as if the wallet had derived it.

**In 0.4.0 you must fill this record in by hand, and that is a sharp edge.**
Four of the five fields are a rendering of `raw`, and the generated
field-by-field initializer will take whatever is put in them -- there is no
check, because the record crosses the boundary field by field rather than
through a decoder. The value you hand in is the value that is forwarded: an
`X402EscalationRequest` is serialised as it stands and passed to your
`AgentEscalationHost`, so a `display` an app filled in itself is the string the
owner ends up reading. The constructors that compute these fields for you
arrived in **0.5.0**, not here; see "Constructors for the untrusted records"
under that version.

**Do not put a warning badge behind `hiddenRemoved`.** It fires on honest text.
The strip set covers the whole `Default_Ignorable_Code_Point` set, and part of
that set is ordinary orthography: U+200C is required Persian spelling, U+200D
holds Devanagari conjuncts and emoji ZWJ sequences such as the family emoji
together, and U+FE0F is how an emoji asks for its colour form. Each sets the
flag, and each is dropped from `display` -- which in the Persian case changes
the word. So a badge behind this flag would accuse a large share of legitimate
merchants, and `display` is lossy for the same inputs. Narrowing the set so the
flag means what a screen would want it to mean is not in this release.

`display` is a rendering, NOT a safety verdict. It cannot tell whether the
sentence is true, and it does not touch look-alike letters or right-to-left
scripts. A screen must still label the value as something somebody else wrote.

**`webOrigin`.** An optional `{scheme, host, port?}` naming the document the
payment was demanded from. Nothing signs it and nothing binds it to the host
that reported it -- it travels the same unsigned, agent-side path as the text
above -- so it is a CLAIM. Do not word it "verified" or "attested" on a
screen. What the shape buys, and the whole of what it buys, is that the claim
cannot smuggle a path, a query or a credential inside it. Pass `null` where
there is no document to read: a headless agent has no address bar, and an
invented origin is worse than none.

Operations that change signature:

* `agent.escalate_x402_authorization` -- the escalation request's `resourceUrl`
  and `resourceDescription` become `UntrustedText`, and it gains `webOrigin`.
* `owner.prepare_x402_authorization` -- the sign-request summary it takes
  carries the same two changes: `contextNote` is an `UntrustedText`, and the
  summary gains the same optional `webOrigin`.
* `owner.prepare_mpp_charge`, `owner.prepare_solana_transfer_webauthn` and
  `owner.prepare_solana_escalate_refill_webauthn` -- same summary, same two
  changes. On the request kinds those summaries carry,
  `solanaEscalateRefill.resourceUrl` / `.resourceDescription` and
  `lightningEscalateRefill.resourceDescription` and
  `mppCharge.resourceDescription` become `UntrustedText` too.
  `mppCharge.resourceUrl` stays a `String`: the engine re-reads that exact
  field, parses it and refuses the charge unless the challenge's `realm` names
  the same host, so handing it a sanitised value would break the comparison it
  exists for. That check reaches the HOST and nothing else -- the path, the
  query and the fragment are unconstrained agent-supplied text. Render the host
  if you want to show where the charge came from; rendering the whole string
  puts text with none of `UntrustedText`'s protection beside fields that have
  it.

**A silent JSON break, with no compiler to catch it.** The
`AgentEscalationHost.escalateX402Authorization` callback is handed the
escalation request as a JSON *string*, so its shape changed without its
signature changing. `resourceUrl` and `resourceDescription` are now OBJECTS
(`{"raw": "...", "display": "...", ...}`) where they were bare strings, and a
`webOrigin` object may be present. A host that reads those keys as strings
stops finding text there and will not be told by the compiler. Read
`resourceDescription.display` to show it and `resourceDescription.raw` to
forward it. The same applies to the sign-request summary's `contextNote` where
a host handles it as JSON rather than as a typed value.

### Who a payment pays

The policy engine can be told WHO a payment pays, and refuses to sign a
third-party EVM transfer to an address it cannot show the wallet having paid
before. One agent-tier operation changes its signature:

| operation | what changed |
|---|---|
| `agent.authorize` | its `PolicyIntent` gains `recipient` -- the address the value is addressed to, which for an ERC-20 payment is a word inside the calldata and not the transaction's `to` |

Why it exists: every limit the owner sets is about AMOUNT. An attacker driving
the agent does not need a large payment, it needs a payment to an address it
controls, and a small one satisfies every cap. So a payee the chain cannot
show this wallet having paid before goes to the owner regardless of amount.

**Exactly which requests the gate covers**, because the sentence above is
easy to read more widely than it is true:

- Commands: `transfer`, `send`, `send_transaction`. **Not `x402_payment` and
  not `agent.pay`.** An x402 payment's payee is the `payTo` inside the
  merchant's 402 challenge, not a field of the command input -- the input is a
  URL -- so covering it means checking where that challenge is parsed, which
  is a separate change and is not in this release.
- Chains: EVM only. A Solana third-party `transfer` now escalates
  unconditionally, because nothing in the request establishes which account
  pays: the session context carries the EVM Safe address, and the vault named
  in the intent is supplied by the caller, so answering from it would let a
  caller pick a payment history that suits them.
- The payer is the wallet the request EXECUTES against, from the session
  context. A request naming a different paying wallet escalates rather than
  being answered about the wallet it named.

`recipient` is optional on the wire, and leaving it out is not the cheap way
past the gate: a third-party transfer that names no payee escalates, as does
one on a host with no way to check. A self-to-self refill is unaffected --
it names no payee and is not gated on one.

What it is worth, stated plainly: nothing against an attacker who has taken
the host process, because that attacker calls the signer and never asks the
engine. It works against a model driving an honest, signed binary -- the model
writes the intent but does not control the code that reads it, so it cannot
skip the escalation. The security boundary is still the on-chain mandate; this
is a gate inside the binary that the mandate does not cover.

And what it does not change here, measured rather than assumed: every
third-party EVM transfer through this package already reached the owner and
still does. A separate gate runs ahead of the payee check and asks whether the
payment can pay for its own gas -- the fee the chain charges to move the money
-- and this package has no way to answer that, so it escalates before the
payee is ever considered. The payee reader is wired here so the engine can
answer the payee question at all; nothing on this package turns on it yet.

Wiring a gas reader into this binding would not change that, which is worth
stating because it is the obvious thing to reach for. The rail that answers
the gas question is the executor module paying its own fee out of a USDC float
it holds, and that rail is compiled into the core only under a feature this
package does not turn on. With it off the one reader that exists answers
"cannot tell" on every call, which is the same escalation a host with no
reader gets, and the submit path agrees rather than merely coinciding: under
that same switch it refuses to send a v3-module transfer at all, so a silent
verdict would have nothing to execute it. Turning the rail on for a phone is a
decision about where that float may be spent, not a missing line of wiring.

What this binding does wire, so the one omission is not read as three: the
x402 payment rail reader and the payee-history reader are both attached. Only
the gas reader is left out, and only because on this package it would have
nothing to read.

The two new operations change nothing existing. `agent.authorize` does: its
`PolicyIntent` gains `recipient`, so a host that builds one by hand needs the
extra field.

### A signer for the Enclave, not an example of one

The package ships a Secure Enclave implementation of the `AgentHost` signing
callbacks, so a host no longer writes its own. No operation changes; this is
new code, not a new contract.

`SecureEnclaveSigner` is the key itself: it creates a P-256 key inside the
Secure Enclave, stores the Enclave's opaque blob in the keychain under an
account name the app chooses, reloads it on the next launch, and signs a
32-byte digest the caller supplies. It imports only CryptoKit and Foundation,
so it can be used on its own by a host that does not want the rest.
`SecureEnclaveAgentHost` is the three-method adapter over it: `signerBacking()`
reports `.deviceHardware(kind: .secureEnclave)`, `publicKey()` returns the
uncompressed x9.63 point as 130 hex characters, and `signDigest(digestHex:)`
returns `r || s` as 128 hex characters.

Why ship it rather than document it: there is one correct answer on an Apple
device, so every app writes the same three methods -- and the copy an app
pastes is the copy that drifts, in the one direction that matters. A key in
the Enclave cannot be read off the disk, so an attacker who copies the file
gets nothing and an attacker running code on the unlocked device stops being
able to sign the moment they lose that foothold. A software key erases that
distinction permanently.

Two consequences a host should know before adopting it. `isAvailable` reporting
`false` is not a reason to fall back to a software key: the honest answer is to
declare the agent relay-only and send every write to the owner. And
`signDigest(digestHex:)` refuses anything that is not exactly 64 hexadecimal
characters rather than padding or truncating, because a digest that is the
wrong length is a caller bug and signing it would produce a valid signature
over the wrong thing.

### Naming a payment

`agent.pay` takes one new optional field, `idempotencyKey`. Leave it out and
the call behaves exactly as it did in 0.3.0. Put a name on the payment and the
name decides the EIP-3009 authorization nonce the payment carries, so an agent
that crashed mid-payment and retried under the same name presents an
authorization the token contract has already honoured -- and the
contract refuses it. The exactly-once record is the chain's, not this SDK's:
it survives the crash, the process and this package, and no Paygent server is
in the path. The key is printable ASCII, at most 128 bytes, and a key the
three host languages would disagree about byte-for-byte is refused before
anything is signed.

Only the x402 EIP-3009 rails can carry a name, and which rail answers is read
off the server's own 402 after the call was made. So a named call on any other
rail is REFUSED rather than paid with the name dropped: Lightning (L402), MPP,
the ERC-4337 UserOp scheme and Solana `exact` all throw a request error, having
signed nothing and sent nothing. A call that returns a result is one whose name
was honoured. A caller that would rather pay than be refused retries without
the name, accepting that a second payment is then possible.

One row joins the agent tier:

| operation | what it does |
|---|---|
| `agent.payment_key_status` | what the token contract knows about one idempotency key: for each address that could have paid under it, the authorization nonce that address derives and whether that nonce has been consumed |

It takes an optional `wallet` -- leave it out for the host's active one -- and
asks about both addresses that could have been the payer, the wallet and its
executor module, because the nonce is derived from whichever one signed.

Three limits, all of them in the answer rather than behind it.

The record is per token per chain. Naming a key does pin the token when the
call also named one: `token` is ordinarily a preference the negotiation may
fall back from, and a name turns it into a constraint, so a 402 that offers
nothing in that token is refused rather than paid in another. The CHAIN is not
pinned -- there is no chain field on the call -- so a server that re-quotes a
retry onto another chain moves it onto another contract, and both attempts can
settle.

`consumed` says a nonce was consumed, not that your payment settled. The
contract's bit is set by a `transferWithAuthorization` for any amount or
recipient signed under the same name, and equally by `cancelAuthorization`,
which moves no money.

`consumed: false` is not a verdict that nothing happened. The read is an
`eth_call` at the latest block the answering node has, so a payment in flight,
in the mempool, or mined on a head that node has not caught up to reads false.
Poll until it is true or until the authorization's own validity window has
passed; do not read one false as licence to pay again.

### A payment failure says whether money moved

How `agent.pay` FAILS changes too, and separately from the field above: a
failure no longer arrives as `MobileError.Rpc`. Most ways a payment can fail
mean no money moved -- but `settlementUnknown`, `unattributedSettlement` and
`lightningSilent` mean it may already have landed, and no rail here refunds. An
app that read "this threw" as "this did not pay" and retried would pay twice,
so the failure is now two cases a `switch` has to tell apart:

| case | what it means |
|---|---|
| `MobileError.PayFailed(kind:detail:)` | nothing was paid; safe to retry as it stands |
| `MobileError.PaySettlementUnknown(kind:detail:)` | money may have moved; do not retry without checking |

Which case a failure becomes is decided once, in Rust, in the same declaration
that lists the failure kinds: each kind is written down with the case it
belongs to, so a kind added later does not compile until somebody has said
whether retrying it can pay twice -- and the browser binding reads the same
answer. The case is the whole of the retry question; `kind` is beside it so an
app can also tell an unwired rail from a refused key without matching on
message text. It is a
`PayErrorKind`; it is `public` in the `PaygentMobileCore` module alongside
`MobileError`, so naming it needs no second import, and each of its cases
carries the failure's own documentation.

`detail` is the error's own text, unchanged -- on a rail whose payer settles
first it is the only record of the credential the money bought, so log the
string rather than a category. What that text no longer carries is the
`"rpc error: "` prefix, which named a transport for failures that are usually
not transport failures.

A host on 0.3.0 that only printed the error keeps working. One that matched
`MobileError.Rpc` to detect a failed payment stops matching payment failures
altogether -- but whether the compiler says so depends on how it matched. An
exhaustive `switch` over `MobileError` with no `default:` does fail to build,
which is the outcome to want. `if case .Rpc(let detail) = error`, or a `switch`
that ends in `default:`, keeps compiling and quietly takes the other branch;
the Kotlin pair is `when (e) { is MobileException.Rpc -> ... else -> ... }`,
the error type being named `MobileException` there and `MobileError` here. So
grep the host for `.Rpc` -- the case is spelled with a capital R in both
bindings -- rather than trusting the build to find it.

## 0.3.0

The Solana owner ops price the rent of the accounts they create, and the
binding no longer takes a fee. No agent-tier operation arrives or moves; the
agent tier is unchanged from 0.2.0.

Owner tier (reachable, unsupported on this package): every
`prepare_solana_*` operation drops its `maxFee` / `actualFee` arguments -- the
engine computes the schedule the owner signs, from the operation and the SOL
price this release pins -- and `owner.solana_owner_op_fees` takes the operation
it is pricing. `owner.prepare_solana_add_agent_webauthn` takes the agent's
Ed25519 key (`agentOwner`) instead of a pocket address, and creates the pocket
in the same transaction; `owner.prepare_solana_close_agent_webauthn` no longer
takes a rent destination, which is the wallet's guard account, and the Solana
target of `owner.prepare_agent_disownment` drops the same three fields
(`rentDestination`, `maxFee`, `actualFee`) for the same reason;
`owner.quote_solana_op_fee` takes the operation instead of two fee numbers and
its quote gains `uncoveredUsdc`. Three rows join
the owner tier: `owner.sol_usdc_rate_micros`, `owner.solana_fee_coverage` and
`owner.derive_solana_agent_pocket`. A host on 0.2.0 that calls any of the
changed operations does not compile against this release, which is the point:
the fee it used to pass is not a number it gets to choose.

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
