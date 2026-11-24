import XCTest
import Hitch
import Flynn

@testable import Picaroon

final class PicaroonReassociationTokenTests: XCTestCase {

    private func manager(_ sessionPer: UserSessionPer = .window) -> UserSessionManager<UserSession> {
        let config = ServerConfig(address: "127.0.0.1", port: 0, sessionPer: sessionPer)
        return UserSessionManager<UserSession>(config: config)
    }

    private func newSession(_ sessions: UserSessionManager<UserSession>) -> UserSession {
        return sessions.get(nil, nil)!
    }

    func testSessionIdentifiersCannotReassociate() {
        for mode in [UserSessionPer.window, .browser] {
            let sessions = manager(mode)
            let session = newSession(sessions)
            let javascript = session.unsafeJavascriptSessionUUID
            let cookie = session.unsafeCookieSessionUUID

            // even with an outstanding token, the session's own identifiers do not move it
            guard let token = session.unsafeAllowReassociation() else { return XCTFail() }

            XCTAssertFalse(sessions.get(nil, javascript) === session, "mode \(mode)")
            XCTAssertFalse(sessions.get(UUID().uuidHitch, javascript) === session, "mode \(mode)")
            XCTAssertNil(sessions.reassociate(reassociationToken: javascript, cookieSessionUUID: nil), "mode \(mode)")
            XCTAssertNil(sessions.reassociate(reassociationToken: cookie, cookieSessionUUID: nil), "mode \(mode)")
            XCTAssertEqual(session.unsafeJavascriptSessionUUID, javascript, "mode \(mode)")

            // and those attempts did not burn the real token
            XCTAssertTrue(sessions.reassociate(reassociationToken: token, cookieSessionUUID: nil) === session, "mode \(mode)")
        }
    }

    func testTokenIsUnrelatedToSessionIdentifiers() {
        let sessions = manager()
        let session = newSession(sessions)
        guard let token = session.unsafeAllowReassociation() else { return XCTFail() }
        XCTAssertNotEqual(token, session.unsafeJavascriptSessionUUID)
        XCTAssertNotEqual(token, session.unsafeCookieSessionUUID)
        XCTAssertNotNil(UserSessionManager<UserSession>.validated(token))
    }

    func testReassociationRequiresToken() {
        let sessions = manager()
        let session = newSession(sessions)
        XCTAssertNil(sessions.reassociate(reassociationToken: UUID().uuidHitch, cookieSessionUUID: nil))
        XCTAssertNil(sessions.reassociate(reassociationToken: session.unsafeJavascriptSessionUUID, cookieSessionUUID: nil))
    }

    func testTokenIsSingleUse() {
        let sessions = manager()
        let session = newSession(sessions)
        guard let token = session.unsafeAllowReassociation() else { return XCTFail() }

        XCTAssertTrue(sessions.reassociate(reassociationToken: token, cookieSessionUUID: nil) === session)
        XCTAssertNil(sessions.reassociate(reassociationToken: token, cookieSessionUUID: nil))
    }

    func testTokenExpires() {
        let sessions = manager()
        let session = newSession(sessions)
        guard let token = session.unsafeAllowReassociation(timeout: 0) else { return XCTFail() }
        Thread.sleep(forTimeInterval: 0.01)
        XCTAssertNil(sessions.reassociate(reassociationToken: token, cookieSessionUUID: nil))

        // an expired token is consumed; a fresh one still works
        guard let fresh = session.unsafeAllowReassociation() else { return XCTFail() }
        XCTAssertTrue(sessions.reassociate(reassociationToken: fresh, cookieSessionUUID: nil) === session)
    }

    func testNewTokenRevokesPrevious() {
        let sessions = manager()
        let session = newSession(sessions)
        guard let first = session.unsafeAllowReassociation() else { return XCTFail() }
        guard let second = session.unsafeAllowReassociation() else { return XCTFail() }
        XCTAssertNotEqual(first, second)
        XCTAssertNil(sessions.reassociate(reassociationToken: first, cookieSessionUUID: nil))
        XCTAssertTrue(sessions.reassociate(reassociationToken: second, cookieSessionUUID: nil) === session)
    }

    func testRedemptionRotatesBothIdentifiers() {
        let sessions = manager()
        let session = newSession(sessions)
        let oldCookie = session.unsafeCookieSessionUUID
        let oldJavascript = session.unsafeJavascriptSessionUUID
        guard let token = session.unsafeAllowReassociation() else { return XCTFail() }

        XCTAssertTrue(sessions.reassociate(reassociationToken: token, cookieSessionUUID: nil) === session)
        XCTAssertNotEqual(session.unsafeCookieSessionUUID, oldCookie)
        XCTAssertNotEqual(session.unsafeJavascriptSessionUUID, oldJavascript)

        // old identifiers lead nowhere; new ones lead to the session
        XCTAssertFalse(sessions.get(oldCookie, oldJavascript) === session)
        XCTAssertTrue(sessions.get(session.unsafeCookieSessionUUID, session.unsafeJavascriptSessionUUID) === session)
    }

    func testRedemptionKeepsPresentersLiveCookie() {
        let sessions = manager()
        let session = newSession(sessions)
        guard let token = session.unsafeAllowReassociation() else { return XCTFail() }

        // the returning browser was given a throwaway session (and cookie) on its fresh page load
        let throwaway = newSession(sessions)
        XCTAssertTrue(sessions.reassociate(reassociationToken: token,
                                           cookieSessionUUID: throwaway.unsafeCookieSessionUUID) === session)
        XCTAssertEqual(session.unsafeCookieSessionUUID, throwaway.unsafeCookieSessionUUID)
        XCTAssertNotEqual(session.unsafeJavascriptSessionUUID, throwaway.unsafeJavascriptSessionUUID)
        XCTAssertTrue(sessions.get(throwaway.unsafeCookieSessionUUID, throwaway.unsafeJavascriptSessionUUID) === throwaway)
    }

    func testTokenDiesWithSession() {
        let sessions = manager()
        let session = newSession(sessions)
        guard let token = session.unsafeAllowReassociation() else { return XCTFail() }
        sessions.end(session)
        XCTAssertNil(sessions.reassociate(reassociationToken: token, cookieSessionUUID: nil))
        XCTAssertNil(session.unsafeAllowReassociation())
    }

    func testMalformedTokensAreRejected() {
        let sessions = manager()
        let session = newSession(sessions)
        guard let token = session.unsafeAllowReassociation() else { return XCTFail() }
        for bad: Hitch in ["", "x", Hitch(string: token.toString() + "0"), Hitch(string: String(repeating: "A", count: 4096))] {
            XCTAssertNil(sessions.reassociate(reassociationToken: bad, cookieSessionUUID: nil))
        }
        XCTAssertTrue(sessions.reassociate(reassociationToken: token, cookieSessionUUID: nil) === session)
    }

    func testApiModeRedemption() {
        let sessions = manager(.api)
        let session = newSession(sessions)
        let oldJavascript = session.unsafeJavascriptSessionUUID
        guard let token = session.unsafeAllowReassociation() else { return XCTFail() }
        XCTAssertTrue(sessions.reassociate(reassociationToken: token, cookieSessionUUID: nil) === session)
        XCTAssertFalse(sessions.get(nil, oldJavascript) === session)
        XCTAssertTrue(sessions.get(nil, session.unsafeJavascriptSessionUUID) === session)
    }
}
