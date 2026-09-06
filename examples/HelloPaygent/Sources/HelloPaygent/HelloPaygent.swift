// The smallest app-shaped thing that uses the SDK: a host, and a client built
// over it.

import Foundation
import PaygentMobileCore
import PaygentSdk

/// A host that holds no key and has stored nothing.
///
/// The core reaches back into an app through five protocols, not one:
/// `AgentHost` is the signing key and only that, `AgentSessionHost` is the
/// stored wallet record, and the remaining three each unlock the operations
/// they serve. One type conforms to all five here so that the whole callback
/// surface is visible in one place; a real app is free to split them across
/// its keychain, its store and its owner channel, which is the reason they are
/// separate protocols.
///
/// Every read refuses, which is a legitimate state -- an app that has not been
/// hired by an owner yet is exactly this -- and it makes the shape of the
/// protocols visible without a keychain or a database behind it.
///
/// A real host replaces `signerBacking()` with a truthful answer and serves the
/// reads from whatever it stored when the owner hired it.
public final class StubHost:
    AgentHost,
    AgentSessionHost,
    AgentHistoryHost,
    AgentPocketHost,
    AgentEscalationHost,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var calls: Set<String> = []

    public init() {}

    /// Whether the core has called `name` on this host.
    public func wasCalled(_ name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return calls.contains(name)
    }

    private func record(_ name: String) {
        lock.lock()
        calls.insert(name)
        lock.unlock()
    }

    private func nothingStored(_ name: String) -> AgentHostError {
        record(name)
        return AgentHostError.Unavailable(detail: "\(name): this host has stored nothing")
    }

    // MARK: - AgentHost: the signing key, and nothing else

    // No key of its own, so every write goes to the owner. Said explicitly:
    // a host that stays quiet about what holds its key is treated as having
    // none, and that is the safe direction, but it is not a declaration.
    public func signerBacking() throws -> AgentSignerBacking {
        record("signerBacking")
        return .relayOnly
    }

    public func publicKey() async throws -> String {
        throw nothingStored("publicKey")
    }

    public func signDigest(digestHex: String) async throws -> String {
        throw nothingStored("signDigest")
    }

    // MARK: - AgentSessionHost: the stored wallet record

    public func sessionSnapshot(wallet: String?) async throws -> String {
        throw nothingStored("sessionSnapshot")
    }

    // MARK: - AgentHistoryHost: whatever indexer the app has

    public func transactions(
        wallet: String,
        chainId: UInt64?,
        limit: UInt32?,
        offset: UInt32?
    ) async throws -> String {
        throw nothingStored("transactions")
    }

    // MARK: - AgentPocketHost: the agent's Solana pocket

    public func solanaPocketGet(network: String, mint: String) async throws -> String {
        throw nothingStored("solanaPocketGet")
    }

    public func solanaPocketRefill(
        network: String,
        mint: String,
        amount: String
    ) async throws -> String {
        throw nothingStored("solanaPocketRefill")
    }

    public func solanaPocketSweep(network: String, mint: String) async throws -> String? {
        throw nothingStored("solanaPocketSweep")
    }

    // MARK: - AgentEscalationHost: a way to reach the owner

    public func escalateX402Authorization(requestJson: String) async throws -> String {
        throw nothingStored("escalateX402Authorization")
    }
}

// There is no `balances` or `networks` member on any of these protocols. Both
// are answered inside Rust from the configuration below -- `rpcBase` and the
// optional `tokens` list -- so an app that implements them is never called.

public enum HelloPaygent {
    /// Build a client. `rpcBase` is any Ethereum JSON-RPC endpoint.
    ///
    /// The signer and the session are required; the other three hosts are
    /// optional, and each one left out makes the operations it serves refuse
    /// rather than silently do something else. This example passes all five so
    /// that every refusal is reachable.
    public static func agent(rpcBase: String, host: StubHost) throws -> PaygentAgent {
        let config = ["rpcBase": rpcBase]
        let json = try JSONEncoder().encode(config)
        guard let text = String(data: json, encoding: .utf8) else {
            throw MobileError.InvalidInput(detail: "configuration is not UTF-8")
        }
        return try PaygentAgent(
            configJson: text,
            host: host,
            session: host,
            history: host,
            pocket: host,
            escalation: host
        )
    }
}
