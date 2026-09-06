// The code from the "Paying for a resource" documentation article, as a target
// something compiles.

import PaygentMobileCore
import PaygentSdk

/// What a server's `402` demanded, as this example's caller reads it off the
/// response. Not a type from the SDK: parsing the demand is the app's job on
/// this binding, and this is the smallest shape the escalation needs.
public struct Demand {
    public let payTo: String
    public let asset: String
    public let amountBaseUnits: String
    public let network: String
    public let chainId: UInt64
    public let eip712Name: String
    public let eip712Version: String

    public init(
        payTo: String,
        asset: String,
        amountBaseUnits: String,
        network: String,
        chainId: UInt64,
        eip712Name: String,
        eip712Version: String
    ) {
        self.payTo = payTo
        self.asset = asset
        self.amountBaseUnits = amountBaseUnits
        self.network = network
        self.chainId = chainId
        self.eip712Name = eip712Name
        self.eip712Version = eip712Version
    }
}

/// What the caller of this example learns.
public enum Bought {
    /// The resource arrived. `settlement` is absent when it cost nothing.
    case got(body: String, settlement: PaySettlement?)
    /// Money moved and the resource did not arrive. No refund path.
    case paidAndLost(settlement: PaySettlement?)
    /// The server refused and nothing was paid.
    case refused(status: UInt16)
    /// The owner has to approve this one. Hand it to `Example.escalate`.
    case ownerMustApprove
    /// The call threw. Almost always the attempt was never made and nothing
    /// was paid -- today that includes every `402` on this binding, which has
    /// no payer and throws naming the rail. Not always: a plain `200` carrying
    /// a settlement receipt is thrown too, and then money moved that this call
    /// cannot account for, with the message as the only record of it. The two
    /// arrive as the same `MobileError`, so neither retry on this nor put a
    /// payment in front of the owner on the strength of it: keep the message,
    /// and to pay a demand this binding refused, read that demand off the
    /// server's own `402` first and hand it to `Example.escalate`.
    case failed(MobileError)
}

public enum Example {
    /// Fetch a resource, paying for it if the server asks and the app may.
    public static func buy(
        agent: PaygentAgentProtocol,
        url: String,
        ceilingBaseUnits: String
    ) async throws -> Bought {
        let call = PayCall(
            method: "GET",
            url: url,
            headers: [:],
            bodyBase64: nil,
            wallet: nil,
            maxAmount: ceilingBaseUnits,
            maxSats: nil,
            token: nil
        )

        let result: PayResult
        do {
            result = try await agent.agentPay(call: call)
        } catch let error as MobileError {
            // What an x402 demand looks like on this binding today. No payer is
            // wired into it, so a demand the app is asked to settle comes back
            // as a thrown error naming the rail -- not as `ownerApprovalNeeded`,
            // which would tell a person their owner can approve a payment on a
            // rail nothing here speaks. A `switch` over `PayResult` alone never
            // sees this case, which is why it is caught here rather than left
            // to the caller. It is NOT mapped to `ownerMustApprove`: the same
            // catch receives the receipt of a spend this call could not
            // attribute, and sending that to the owner would pay twice.
            return .failed(error)
        }

        switch result {
        case .served(let response):
            return .got(body: response.bodyBase64, settlement: nil)

        case .paidAndServed(_, _, let settlement, let response):
            return .got(body: response.bodyBase64, settlement: settlement)

        case .paidNotServed(_, _, let settlement, _):
            // The loud one. Money is gone, the resource is not here, and the
            // settlement is the only record of the spend.
            return .paidAndLost(settlement: settlement)

        case .rejected(_, _, let response):
            return .refused(status: response.status)

        case .ownerApprovalNeeded:
            return .ownerMustApprove

        case .pocketTopUpNeeded:
            // A Lightning invoice larger than this app's own pocket. The owner
            // tops the pocket up; they are never asked to pay the merchant.
            return .ownerMustApprove
        }
    }

    /// Put one payment in front of the owner and return what they signed.
    ///
    /// Every field is copied from the server's own demand. Sending anything
    /// else asks the owner to approve a different payment than the one that was
    /// demanded.
    public static func escalate(
        agent: PaygentAgentProtocol,
        wallet: String,
        demand: Demand,
        resourceUrl: String,
        shownToTheOwner: String
    ) async throws -> Eip3009Authorization {
        try await agent.agentEscalateX402Authorization(
            request: X402EscalationRequest(
                chainId: demand.chainId,
                network: demand.network,
                safeAddress: wallet,
                payTo: demand.payTo,
                amount: demand.amountBaseUnits,
                asset: demand.asset,
                maxTimeoutSeconds: 60,
                eip712Name: demand.eip712Name,
                eip712Version: demand.eip712Version,
                resourceUrl: resourceUrl,
                resourceDescription: shownToTheOwner
            )
        )
    }

    /// A person types "1.5"; the wire wants base units.
    public static func ceiling(_ typed: String, decimals: UInt32) throws -> String {
        try Amount.toBaseUnits(input: typed, decimals: decimals)
    }
}
