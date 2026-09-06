import XCTest

// PaygentSdk only. Everything used below is either declared by it (`Amount`) or
// named by one of its aliases, and one import is the ordinary way to consume
// this package. The file next door imports both modules, which is where that
// combination is exercised.
import PaygentSdk

@testable import HelloPaygent

/// These run on a simulator, which is what makes them worth having: they link
/// the downloaded binary and call into it. Anything less proves only that the
/// Swift declarations parse.
final class HelloPaygentTests: XCTestCase {
    /// A pure function across the boundary, in both directions.
    func testAnAmountCrossesTheBoundaryAndComesBack() throws {
        XCTAssertEqual(try Amount.toBaseUnits(input: "1.5", decimals: 6), "1500000")
        XCTAssertEqual(
            try Amount.fromBaseUnits(raw: "1500000", decimals: 6, maxFractionDigits: nil),
            "1.5"
        )
    }

    /// A fraction finer than the token can hold is refused, not rounded away.
    func testAnAmountTooFineForTheTokenIsRefused() {
        XCTAssertThrowsError(try Amount.toBaseUnits(input: "1.0000001", decimals: 6))
    }

    /// The constructor refuses a configuration it cannot use, rather than
    /// building a client that fails later.
    ///
    /// Written with only `PaygentSdk` imported, and that is the point: the
    /// signer and the session hosts are named in this signature, so a protocol
    /// the SDK forgot to re-export fails to compile here.
    func testAClientWithNoRpcEndpointIsRefused() {
        let host = StubHost()
        XCTAssertThrowsError(try PaygentAgent(configJson: "{}", host: host, session: host))
    }

    /// The core calls back into the host across the FFI. This is the direction
    /// a compile cannot check: the host is Swift, called from Rust.
    func testTheCoreReadsTheSessionFromTheHost() async throws {
        let host = StubHost()
        let agent = try HelloPaygent.agent(rpcBase: "https://rpc.paygent.net", host: host)

        // Does not throw by contract: a session that cannot be read is the
        // empty snapshot, which every caller treats as "no wallet".
        _ = await agent.agentSession(wallet: nil)

        XCTAssertTrue(
            host.wasCalled("sessionSnapshot"),
            "the core did not ask the host for the session"
        )
    }
}
