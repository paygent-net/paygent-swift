// The agent-tier surface of PaygentMobileCore, and only that.
//
// PaygentMobileCore is one flat Swift module holding everything the Rust core
// exports: the bounded-spend "agent" operations named below, and a much larger
// set of owner-tier operations that administer the wallet itself. Swift has no
// way to re-export a selection of a module's symbols -- `@_exported import`
// takes all of them or none -- so the selection is made by naming each
// agent-tier type here, over a plain import that is not re-exported. A file
// that imports only PaygentSdk is offered these names and not the rest.
//
// This curates what a developer is offered; it is not an access control.
// SwiftPM puts every module of the package graph on one search path, so a
// consumer who writes `import PaygentMobileCore` still gets the whole surface,
// and both products link the same binary, so neither is smaller than the other.
//
// An alias names a type; the type's members stay declared in PaygentMobileCore.
// A file compiled with the `MemberImportVisibility` upcoming feature (SE-0444)
// can call a member only when the module declaring it is imported in that file,
// so such a file must import PaygentMobileCore as well. Both imports together
// are unambiguous because nothing declared here, aliases aside, shares a name
// with a declaration in PaygentMobileCore: a name both modules declared at top
// level would make every unqualified reference to it an error, and CI checks
// (check-sdk-names-disjoint.sh) that no such name exists.
//
// The list below is the transitive closure of the signatures of `PaygentAgent`
// and of the five host protocols an app implements. Adding an operation to any
// of them without adding the types it names leaves the SDK unable to express
// that operation; no build fails. That has already happened once: the host
// split that turned one `AgentHost` into five left the four new protocols
// unnamed here, so a file importing only PaygentSdk could not write the
// constructor's arguments. `examples/HelloPaygent` is the guard -- it imports
// only PaygentSdk in its tests, so a name missing from this file fails a
// compile rather than a review.

import PaygentMobileCore

// MARK: - The client

/// A bounded-spend delegate. Build one per app and keep it: it holds the store
/// that a payment awaiting the owner's approval is parked in.
///
/// The initializer takes a JSON configuration object with two keys:
/// `rpcBase` (required) is the base URL every chain read and every submission
/// goes through; `paymasterUrl` (optional) is the endpoint that sponsors this
/// agent's transactions, and leaving it out means the transaction pays its own
/// gas. Any other key is refused rather than ignored.
public typealias PaygentAgent = PaygentMobileCore.PaygentAgent

/// The operations `PaygentAgent` offers, as a protocol, so a caller's tests can
/// substitute their own implementation.
public typealias PaygentAgentProtocol = PaygentMobileCore.PaygentAgentProtocol

/// What the app must implement: the key that signs. Three members, and nothing
/// else -- an app that has no store and no indexer still conforms to this.
public typealias AgentHost = PaygentMobileCore.AgentHost

/// The stored wallet record. Required alongside ``AgentHost``: without one
/// there is no wallet to act for.
public typealias AgentSessionHost = PaygentMobileCore.AgentSessionHost

/// Transaction history, from whatever indexer the app has. Optional; without
/// it `agentTransactions` refuses, because no public JSON-RPC endpoint can
/// answer "the history of this address".
public typealias AgentHistoryHost = PaygentMobileCore.AgentHistoryHost

/// The agent's Solana pocket. Optional; without it the three pocket
/// operations refuse.
public typealias AgentPocketHost = PaygentMobileCore.AgentPocketHost

/// A way to put a payment in front of the owner. Optional; without it an x402
/// escalation refuses by name rather than being signed locally.
public typealias AgentEscalationHost = PaygentMobileCore.AgentEscalationHost

// MARK: - Errors

public typealias MobileError = PaygentMobileCore.MobileError
public typealias AgentHostError = PaygentMobileCore.AgentHostError

// MARK: - What backs the app's signing key

public typealias AgentSignerBacking = PaygentMobileCore.AgentSignerBacking
public typealias AgentHardwareKind = PaygentMobileCore.AgentHardwareKind

// MARK: - Wallet state

public typealias SessionSnapshot = PaygentMobileCore.SessionSnapshot
public typealias OwnerSummary = PaygentMobileCore.OwnerSummary
public typealias ChainDeploymentSummary = PaygentMobileCore.ChainDeploymentSummary
public typealias SolanaWalletSummary = PaygentMobileCore.SolanaWalletSummary
public typealias TokenBalance = PaygentMobileCore.TokenBalance
public typealias TransactionSummary = PaygentMobileCore.TransactionSummary

// MARK: - The spend decision

public typealias PolicyIntent = PaygentMobileCore.PolicyIntent
public typealias IntentAmount = PaygentMobileCore.IntentAmount
public typealias PolicyDecision = PaygentMobileCore.PolicyDecision
public typealias PolicyAction = PaygentMobileCore.PolicyAction
public typealias SigningPath = PaygentMobileCore.SigningPath
public typealias AuthLevel = PaygentMobileCore.AuthLevel
public typealias CommandContext = PaygentMobileCore.CommandContext
public typealias Surface = PaygentMobileCore.Surface
public typealias SigningCapability = PaygentMobileCore.SigningCapability
public typealias HardwareKind = PaygentMobileCore.HardwareKind

// MARK: - Moving money

public typealias DeployUserOpRequest = PaygentMobileCore.DeployUserOpRequest
public typealias TransferUserOpRequest = PaygentMobileCore.TransferUserOpRequest
public typealias SolanaPocketInfo = PaygentMobileCore.SolanaPocketInfo
public typealias SolanaPocketReceipt = PaygentMobileCore.SolanaPocketReceipt
public typealias Period = PaygentMobileCore.Period
public typealias X402EscalationRequest = PaygentMobileCore.X402EscalationRequest
public typealias Eip3009Authorization = PaygentMobileCore.Eip3009Authorization

/// The identifier a submitted transaction is tracked by. Upstream this is a
/// named wrapper over a string, and the binding carries it as a plain `String`,
/// so this alias is a name for the return value rather than a distinct type.
public typealias UserOpHash = PaygentMobileCore.UserOpHash

// MARK: - Paying for a resource

/// What to ask for, and what the caller is willing to pay for it. Carries no
/// payment rail: which one the server speaks is read off its response.
public typealias PayCall = PaygentMobileCore.PayCall

/// What came of asking for a resource that may cost money.
///
/// Switch on every case. `paidNotServed` in particular is a result and not a
/// thrown error: the money is gone and the resource did not arrive, on rails
/// that have no refund path, so a caller that only inspects thrown errors will
/// miss it.
public typealias PayResult = PaygentMobileCore.PayResult

public typealias PayResponse = PaygentMobileCore.PayResponse
public typealias PaySettlement = PaygentMobileCore.PaySettlement

// MARK: - Amounts

/// The three amount conversions the operations above require, forwarded by
/// hand because a `typealias` names a type and cannot name a function. Every
/// amount crosses as text: no number type in Swift can carry an 18-decimal
/// token balance without rounding it.
///
/// They live under this namespace rather than as free functions so that a file
/// importing both `PaygentSdk` and `PaygentMobileCore` sees one candidate for
/// each name, not two identical ones.
public enum Amount {
    /// Convert a human decimal amount ("1.5") into its base-units integer string
    /// ("1500000"), given the token's decimal places. This is the form
    /// `agentRefillSolanaPocket` takes. Fraction digits finer than the token's
    /// resolution are refused rather than rounded away.
    public static func toBaseUnits(input: String, decimals: UInt32) throws -> String {
        try PaygentMobileCore.amountToBaseUnits(input: input, decimals: decimals)
    }

    /// Render a base-units integer string ("1500000") as a human decimal amount
    /// ("1.5"), given the token's decimal places -- the inverse, for displaying a
    /// `TokenBalance`. `maxFractionDigits` truncates the displayed fraction; pass
    /// `nil` to show the amount exactly.
    public static func fromBaseUnits(
        raw: String,
        decimals: UInt32,
        maxFractionDigits: UInt32?
    ) throws -> String {
        try PaygentMobileCore.amountFromBaseUnits(
            raw: raw, decimals: decimals, maxFractionDigits: maxFractionDigits
        )
    }

    /// Convert a base-units integer string ("1000000") into the "0x"-prefixed
    /// hexadecimal form ("0xf4240") that `TransferUserOpRequest.amountBaseUnits`
    /// carries. A value that is not a whole base-10 number, or that will not fit
    /// in 256 bits, is refused rather than coerced.
    public static func decimalToU256Hex(decimal: String) throws -> String {
        try PaygentMobileCore.amountDecimalToU256Hex(decimal: decimal)
    }
}
