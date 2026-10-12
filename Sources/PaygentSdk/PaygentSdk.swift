// The agent surface of the Rust core, re-exported whole.
//
// What a consumer may reach is decided by which binary it links, not by this
// file. The public paygent-swift package is built agent-only
// (`--no-default-features`), so its PaygentMobileCore module holds the agent
// surface and nothing else: `PaygentAgent`, the five host protocols, the types
// their signatures name, and the amount and untrusted-text helpers. The owner
// tier is not in that binary at all. So there is nothing left to curate, and
// `import PaygentSdk` brings the whole of it into scope.
//
// The native authorizers vendor a different build (`full`, owner tier and
// Lightning included) through the internal `mobile-v*` package, and import
// PaygentMobileCore directly.
//
// Every name this module declares is visible next to every name the core
// declares, so the two must never share one: an unqualified reference to a
// name both declare is ambiguous. CI checks that (check-sdk-names-disjoint.sh).

@_exported import PaygentMobileCore

// MARK: - Amounts

/// The three amount conversions the operations above require, forwarded by
/// hand because a `typealias` names a type and cannot name a function. Every
/// amount crosses as text: no number type in Swift can carry an 18-decimal
/// token balance without rounding it.
///
/// They live under this namespace rather than as free functions so that no
/// name here collides with the core function each one forwards to.
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

// MARK: - Text somebody else wrote

/// The constructors for ``UntrustedText`` and ``WebOrigin``, under a namespace
/// for the same reason as ``Amount``.
///
/// Reach for these rather than the generated initializers. Both types carry
/// fields derived from what was supplied -- the sanitised form of the text, and
/// the parts of the origin -- and the generated initializer will take whatever
/// is put in them. The escalation request is forwarded as it stands, so a
/// `display` an app invents is the string the owner is shown.
public enum Untrusted {
    /// Sanitise text somebody else supplied into the form an approval screen
    /// may render: characters that show as nothing or reverse their neighbours
    /// removed, runs of whitespace collapsed, and the result capped at 200
    /// characters so it cannot scroll the amount off the card.
    ///
    /// Never fails. Every input produces a value, because the payment still has
    /// to be decided; what had to change is reported by the flags on the
    /// result. Those flags are not a warning badge -- read ``UntrustedText``
    /// before wiring one to a screen.
    public static func parse(_ raw: String) -> UntrustedText {
        PaygentMobileCore.untrustedTextParse(raw: raw)
    }

    /// The same, for a field that may be absent. Text that sanitises to nothing
    /// -- absent, empty, or only whitespace -- comes back `nil`, so a screen
    /// never reserves space for a blank description.
    public static func parseOptional(_ raw: String?) -> UntrustedText? {
        PaygentMobileCore.untrustedTextParseOptional(raw: raw)
    }

    /// Read a whole origin -- scheme, host, port -- out of a URL-shaped string.
    ///
    /// Throws when the input is not a URL, does not speak `http` or `https`,
    /// names no host, carries a user or password, or carries anything past the
    /// host: a path, a query or a fragment. So a resource URL is refused rather
    /// than quietly trimmed. That is deliberate: `https://bank.example@evil.test`
    /// reads as the bank and resolves to the attacker, and trimming it would put
    /// the attacker's origin on screen under the bank's name.
    public static func webOrigin(_ input: String) throws -> WebOrigin {
        try PaygentMobileCore.webOriginParse(input: input)
    }
}
