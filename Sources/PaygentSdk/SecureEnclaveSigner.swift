// A P-256 signing key held in this device's Secure Enclave, in the shape the
// agent binding asks for: a hex public key and a hex signature over a hex
// digest.
//
// Nothing here imports PaygentMobileCore. It is deliberately a plain CryptoKit
// type so that it can be read, tested and reused on its own; the adapter that
// presents it to the binding is a separate file.
//
// What "Secure Enclave" buys, precisely: the private key is generated inside a
// separate coprocessor and never exists in this process's memory. What the
// keychain stores, and what `persistedBlob` returns, is an encrypted reference
// that only this device's Enclave can use -- copying it to another machine
// yields nothing. So an attacker who reads the file can not sign; an attacker
// running code on the unlocked device can ask the Enclave to sign, and stops
// being able to the moment they lose that foothold. Preserving that difference
// is the whole reason this type exists rather than a key on disk.

import CryptoKit
import Foundation

/// A 32-byte value to be signed as-is.
///
/// CryptoKit will sign a digest rather than hashing a message for you, but it
/// gives `SHA256Digest` no public initializer, so there is no way to hand it 32
/// bytes that came from somewhere else. Conforming our own type to `Digest` is
/// the supported route: the protocol is what `signature(for:)` takes, and the
/// only thing it needs is the bytes and their count.
///
/// The bytes are used exactly as given. This type performs no hashing, which is
/// the point -- the digest was computed by the caller, over a payload this file
/// never sees.
struct RawDigest: Digest {
    static var byteCount: Int { 32 }

    let bytes: [UInt8]

    func makeIterator() -> Array<UInt8>.Iterator { bytes.makeIterator() }

    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try bytes.withUnsafeBytes(body)
    }

    static func == <D: DataProtocol>(lhs: Self, rhs: D) -> Bool {
        lhs.bytes.count == rhs.count && lhs.bytes.elementsEqual(rhs)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(bytes) }
}

/// A signing key in the Secure Enclave, created once and then reloaded from the
/// keychain on every later launch.
///
/// Create one at app start and keep it. The key it wraps IS the agent's
/// identity: the chain records its public key as the module signer, and there
/// is no rotation primitive, so losing the keychain item means adding a new
/// owner key and removing the old one, not recovering this one.
/// `@unchecked Sendable` because the binding calls `signDigest` from Rust's
/// executor and may call it concurrently. Nothing here is mutable after
/// construction, and CryptoKit signing keys are value types that hold no state
/// across a signature, so concurrent calls are independent -- the Enclave
/// serializes them itself.
public final class SecureEnclaveSigner: @unchecked Sendable {
    /// Why a signer could not be built, or could not sign.
    public enum Failure: Error, CustomStringConvertible {
        /// This device has no Secure Enclave, or the process may not reach it.
        /// Simulators and Intel Macs without a T2 report this, and so does a
        /// GitHub-hosted macOS runner.
        case noSecureEnclave
        /// The keychain refused. Carries the raw `OSStatus` because the
        /// security framework's failures are distinguished only by it.
        case keychain(OSStatus)
        /// The data-protection keychain refused this process. On macOS that
        /// means the binary is not signed with a `keychain-access-groups`
        /// entitlement and an embedded provisioning profile that authorizes
        /// it: a command-line tool or an XPC service needs both. Carries
        /// `errSecMissingEntitlement` (-34018) or
        /// `errSecInteractionNotAllowed` (-25308). On iOS, -25308 can instead
        /// mean the device has not been unlocked since it booted.
        case missingKeychainEntitlement(OSStatus)
        /// The stored key reference did not load. The device was restored from
        /// another device's backup, or the item was written by something else.
        case unusableStoredKey(String)
        /// The digest was not 64 hexadecimal characters.
        case malformedDigest(String)
        /// The Enclave refused to sign. Most often the user cancelled the
        /// biometric prompt, or the device is locked.
        case signingFailed(String)

        public var description: String {
            switch self {
            case .noSecureEnclave:
                return "this device has no usable Secure Enclave"
            case .keychain(let status):
                return "keychain refused with OSStatus \(status)"
            case .missingKeychainEntitlement(let status):
                return "the data-protection keychain refused with OSStatus \(status): "
                    + "sign this binary with a keychain-access-groups entitlement and "
                    + "embed a provisioning profile that grants it"
            case .unusableStoredKey(let detail):
                return "the stored key reference did not load: \(detail)"
            case .malformedDigest(let detail):
                return "digest must be 64 hex characters: \(detail)"
            case .signingFailed(let detail):
                return "the Secure Enclave refused to sign: \(detail)"
            }
        }
    }

    /// Whether this device can hold a key in its Secure Enclave at all.
    ///
    /// Check it before constructing, and treat `false` as "this app has no
    /// local key" rather than as a reason to fall back to a software key. A
    /// software key can be copied off the disk and reused anywhere, which is
    /// exactly the property the whole design is built to deny; the honest
    /// answer is to declare the agent relay-only and let every write go to the
    /// owner.
    public static var isAvailable: Bool { SecureEnclave.isAvailable }

    private let key: SecureEnclave.P256.Signing.PrivateKey
    private let account: String
    private let accessGroup: String?

    /// Load the key stored under `account`, creating it on first run.
    ///
    /// `account` names one key in this app's keychain. Use a constant: a value
    /// that varies between launches silently mints a second identity, and the
    /// first one is the one the chain knows.
    ///
    /// `accessGroup` is the keychain access group the item lives in. `nil`
    /// uses the process's default group, the first entry of its
    /// `keychain-access-groups` entitlement. Pass one to share the key between
    /// executables signed by the same team, such as an app and its XPC
    /// service.
    ///
    /// The item lives in the data-protection keychain on every platform. On
    /// iOS that is the only keychain there is. On macOS it is not the default:
    /// the file-based login keychain is, and an XPC service may not write to
    /// that one. Reaching the data-protection keychain requires the binary to
    /// be signed with a `keychain-access-groups` entitlement and to embed a
    /// provisioning profile that grants it. Without them this throws
    /// ``Failure/missingKeychainEntitlement(_:)``; there is no fallback to the
    /// login keychain.
    ///
    /// The item is stored `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` --
    /// readable by a background launch once the user has unlocked the device
    /// since boot, and excluded from backups and from iCloud Keychain, so the
    /// reference cannot travel to a device whose Enclave could not use it
    /// anyway.
    public convenience init(account: String, accessGroup: String? = nil) throws {
        guard SecureEnclave.isAvailable else { throw Failure.noSecureEnclave }

        let query = Self.keychainQuery(account: account, accessGroup: accessGroup)
        if let blob = try Self.loadBlob(query: query) {
            let key: SecureEnclave.P256.Signing.PrivateKey
            do {
                key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob)
            } catch {
                throw Failure.unusableStoredKey(String(describing: error))
            }
            self.init(key: key, account: account, accessGroup: accessGroup)
            return
        }

        let key: SecureEnclave.P256.Signing.PrivateKey
        do {
            key = try SecureEnclave.P256.Signing.PrivateKey()
        } catch {
            throw Failure.unusableStoredKey(String(describing: error))
        }
        try Self.storeBlob(key.dataRepresentation, query: query)
        self.init(key: key, account: account, accessGroup: accessGroup)
    }

    private init(
        key: SecureEnclave.P256.Signing.PrivateKey,
        account: String,
        accessGroup: String?
    ) {
        self.key = key
        self.account = account
        self.accessGroup = accessGroup
    }

    /// The signing public key as 130 hexadecimal characters: SEC1-uncompressed,
    /// so `04` followed by the 32-byte X and the 32-byte Y.
    ///
    /// This is the form the agent binding's `publicKey` returns, and the form
    /// the on-chain module stores, so it is what identifies this agent.
    public func publicKeyHex() -> String {
        Self.hex(key.publicKey.x963Representation)
    }

    /// Sign a 32-byte digest given as 64 hexadecimal characters, returning the
    /// raw P-256 signature as 128 hexadecimal characters: the 32-byte `r`
    /// followed by the 32-byte `s`.
    ///
    /// Not DER. The on-chain verifier takes the two scalars directly, and
    /// CryptoKit's `rawRepresentation` is already exactly that concatenation.
    ///
    /// The digest is signed as it arrived. Nothing here inspects what it
    /// commits to, which is why the binding computes it: a host that could
    /// choose what gets hashed could sign something other than the transaction
    /// the owner agreed to.
    public func signDigest(_ digestHex: String) throws -> String {
        let bytes = try Self.decodeDigest(digestHex)
        let signature: P256.Signing.ECDSASignature
        do {
            signature = try key.signature(for: RawDigest(bytes: bytes))
        } catch {
            throw Failure.signingFailed(String(describing: error))
        }
        return Self.hex(signature.rawRepresentation)
    }

    /// Delete this key from the keychain.
    ///
    /// The Enclave key itself becomes unusable with it: the stored blob is the
    /// only handle to it, so this is destruction, not eviction. The agent
    /// cannot sign again, and its public key has to be removed on-chain by the
    /// owner.
    public func destroy() throws {
        let query = Self.keychainQuery(account: account, accessGroup: accessGroup)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Self.keychainFailure(status)
        }
    }

    // MARK: - Keychain

    private static let service = "net.paygent.agent.secure-enclave-key"

    /// The attributes that name this key's keychain item. Every read, write
    /// and delete starts from this, so they cannot disagree about which
    /// keychain or which item they mean.
    ///
    /// `kSecUseDataProtectionKeychain` is set unconditionally. On iOS it
    /// changes nothing. On macOS it selects the data-protection keychain over
    /// the file-based login keychain, which a sandboxed process or an XPC
    /// service cannot write to.
    static func keychainQuery(account: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    /// The error for a keychain status other than success or not-found.
    ///
    /// -34018 and -25308 are what the data-protection keychain answers a
    /// process that is not entitled to it, so they get a failure that names
    /// the entitlement rather than a bare number.
    static func keychainFailure(_ status: OSStatus) -> Failure {
        switch status {
        case errSecMissingEntitlement, errSecInteractionNotAllowed:
            return .missingKeychainEntitlement(status)
        default:
            return .keychain(status)
        }
    }

    private static func loadBlob(query base: [String: Any]) throws -> Data? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw Failure.unusableStoredKey("keychain returned a non-data item")
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw keychainFailure(status)
        }
    }

    private static func storeBlob(_ blob: Data, query: [String: Any]) throws {
        var attributes = query
        attributes[kSecValueData as String] = blob
        attributes[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw keychainFailure(status) }
    }

    // MARK: - Hex

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Decode 64 hex characters into 32 bytes.
    ///
    /// Written out rather than reached for from a library because the binding's
    /// contract is exact: anything that is not 32 bytes is a caller bug, and
    /// silently padding or truncating it would sign a different digest than the
    /// one that was checked.
    static func decodeDigest(_ text: String) throws -> [UInt8] {
        guard text.utf8.count == 64 else {
            throw Failure.malformedDigest("got \(text.utf8.count) characters")
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(32)
        var high: UInt8?
        for character in text.utf8 {
            guard let nibble = Self.nibble(character) else {
                throw Failure.malformedDigest("contains a non-hexadecimal character")
            }
            if let previous = high {
                bytes.append(previous << 4 | nibble)
                high = nil
            } else {
                high = nibble
            }
        }
        return bytes
    }

    private static func nibble(_ character: UInt8) -> UInt8? {
        switch character {
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            return character - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"):
            return character - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"):
            return character - UInt8(ascii: "A") + 10
        default:
            return nil
        }
    }
}
