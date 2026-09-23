// The ready-made ``AgentHost`` most apps should use: a key in this device's
// Secure Enclave.
//
// ``AgentHost`` has three members and no default implementation, so every app
// writes them. Almost every app writes the same three, because there is only
// one correct answer on an Apple device -- which makes a shipped version of it
// worth more than an example of it: the copy an app would otherwise paste is
// the copy that quietly drifts, and the way it drifts is toward a software key.
//
// This is an adapter and nothing else. The key, the keychain and the hex live
// in ``SecureEnclaveSigner``, which imports no binding and can be read on its
// own; this file only presents that type in the shape the binding asks for.

import PaygentMobileCore

/// An ``AgentHost`` backed by a P-256 key in the Secure Enclave.
///
/// ```swift
/// guard let host = SecureEnclaveAgentHost(account: "agent") else {
///     // No Enclave on this device. Do not substitute a software key --
///     // build a relay-only host instead, so every write asks the owner.
///     return
/// }
/// ```
///
/// The initializer is failable rather than throwing because there is exactly
/// one thing a caller can do about any of its failures, and it is the same
/// thing: stop claiming device hardware. Use ``make(account:)`` when the reason
/// matters, for a log or a support screen.
public final class SecureEnclaveAgentHost: AgentHost, @unchecked Sendable {
    private let signer: SecureEnclaveSigner

    /// Build a host over the key stored under `account`, creating the key on
    /// first run. `nil` when this device has no usable Secure Enclave, or the
    /// keychain refused.
    public convenience init?(account: String) {
        guard let signer = try? SecureEnclaveSigner(account: account) else { return nil }
        self.init(signer: signer)
    }

    /// The same thing, with the failure preserved.
    public static func make(account: String) throws -> SecureEnclaveAgentHost {
        SecureEnclaveAgentHost(signer: try SecureEnclaveSigner(account: account))
    }

    /// Wrap a signer the caller already built -- one made under a different
    /// keychain policy, or a stub in a test.
    public init(signer: SecureEnclaveSigner) {
        self.signer = signer
    }

    /// Always `.deviceHardware(kind: .secureEnclave)`.
    ///
    /// Unconditional because the initializer already refused to exist without
    /// an Enclave. A host that answered anything else here would be claiming a
    /// tier it cannot back, and the claim is the only thing that puts the
    /// client on the silent local path.
    public func signerBacking() throws -> AgentSignerBacking {
        AgentSignerBacking.deviceHardware(kind: AgentHardwareKind.secureEnclave)
    }

    public func publicKey() async throws -> String {
        signer.publicKeyHex()
    }

    public func signDigest(digestHex: String) async throws -> String {
        do {
            return try signer.signDigest(digestHex)
        } catch {
            // The binding has one error case, and it carries text. Preserve the
            // signer's own description: "the user cancelled" and "the digest was
            // malformed" are different bugs and the string is all that
            // distinguishes them on the other side.
            throw AgentHostError.Unavailable(detail: String(describing: error))
        }
    }
}
