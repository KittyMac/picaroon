import XCTest
import Hitch
import Flynn

@testable import Picaroon

final class PicaroonSessionFixationTests: XCTestCase {

    private func manager(_ sessionPer: UserSessionPer) -> UserSessionManager<UserSession> {
        let config = ServerConfig(address: "127.0.0.1", port: 0, sessionPer: sessionPer)
        return UserSessionManager<UserSession>(config: config)
    }

    private func attackerUUID() -> Hitch {
        return UUID().uuidHitch
    }

    func testClientChosenIdsAreNotAdopted() {
        for mode in [UserSessionPer.window, .browser, .api] {
            let sessions = manager(mode)
            let chosenCookie = attackerUUID()
            let chosenJavascript = attackerUUID()

            guard let session = sessions.get(chosenCookie, chosenJavascript) else { return XCTFail() }
            XCTAssertNotEqual(session.unsafeCookieSessionUUID, chosenCookie, "mode \(mode)")
            XCTAssertNotEqual(session.unsafeJavascriptSessionUUID, chosenJavascript, "mode \(mode)")

            // and presenting the chosen IDs again must not find that session
            let again = sessions.get(chosenCookie, chosenJavascript)
            XCTAssertFalse(again === session, "mode \(mode)")
        }
    }

    func testMalformedIdsAreIgnored() {
        let sessions = manager(.window)
        let malformed: [Hitch] = [
            "A|B",
            "",
            "not-a-uuid",
            Hitch(string: String(repeating: "A", count: 4096)),
            "4A66CB66-C380-4AB5-9DE5-62199CACF5C|",
            "4A66CB66xC380-4AB5-9DE5-62199CACF5CE"
        ]
        for bad in malformed {
            XCTAssertNil(UserSessionManager<UserSession>.validated(bad))
            guard let session = sessions.get(bad, bad) else { return XCTFail() }
            XCTAssertNotNil(UserSessionManager<UserSession>.validated(session.unsafeCookieSessionUUID))
            XCTAssertNotNil(UserSessionManager<UserSession>.validated(session.unsafeJavascriptSessionUUID))
        }
        XCTAssertNotNil(UserSessionManager<UserSession>.validated("4a66cb66-c380-4ab5-9de5-62199cacf5ce"))
    }

    func testKnownJavascriptIdCannotClobberVictim() {
        let sessions = manager(.window)
        guard let victim = sessions.get(nil, nil) else { return XCTFail() }
        let victimCookie = victim.unsafeCookieSessionUUID
        let victimJavascript = victim.unsafeJavascriptSessionUUID

        // attacker knows the victim's javascript UUID but not the cookie
        guard let attacker = sessions.get(attackerUUID(), victimJavascript) else { return XCTFail() }
        XCTAssertFalse(attacker === victim)
        XCTAssertNotEqual(attacker.unsafeJavascriptSessionUUID, victimJavascript)

        // the victim's indexes are intact
        XCTAssertTrue(sessions.get(victimCookie, victimJavascript) === victim)

        // and the victim's legitimate reassociation still works
        victim._beAllowReassociation()
        XCTAssertTrue(sessions.get(nil, victimJavascript) === victim)
    }

    func testSecondWindowReusesLiveCookie() {
        let sessions = manager(.window)
        guard let window1 = sessions.get(nil, nil) else { return XCTFail() }
        guard let window2 = sessions.get(window1.unsafeCookieSessionUUID, nil) else { return XCTFail() }

        XCTAssertFalse(window1 === window2)
        XCTAssertEqual(window1.unsafeCookieSessionUUID, window2.unsafeCookieSessionUUID)
        XCTAssertNotEqual(window1.unsafeJavascriptSessionUUID, window2.unsafeJavascriptSessionUUID)
        XCTAssertEqual(sessions.numberOfUserSessions(), 2)

        // ending one window must not unindex the other window's shared cookie
        sessions.end(window1)
        XCTAssertTrue(sessions.get(window2.unsafeCookieSessionUUID, window2.unsafeJavascriptSessionUUID) === window2)
        guard let window3 = sessions.get(window2.unsafeCookieSessionUUID, nil) else { return XCTFail() }
        XCTAssertEqual(window3.unsafeCookieSessionUUID, window2.unsafeCookieSessionUUID)
    }

    func testBrowserModeSharedCookieLookup() {
        let sessions = manager(.browser)
        guard let first = sessions.get(nil, nil) else { return XCTFail() }
        XCTAssertTrue(sessions.get(first.unsafeCookieSessionUUID, nil) === first)
        XCTAssertTrue(sessions.get(first.unsafeCookieSessionUUID, attackerUUID()) === first)
    }

    func testEndedSessionIsNotResurrected() {
        let sessions = manager(.window)
        guard let session = sessions.get(nil, nil) else { return XCTFail() }
        let oldCookie = session.unsafeCookieSessionUUID
        let oldJavascript = session.unsafeJavascriptSessionUUID
        sessions.end(session)

        guard let next = sessions.get(oldCookie, oldJavascript) else { return XCTFail() }
        XCTAssertFalse(next === session)
        XCTAssertNotEqual(next.unsafeCookieSessionUUID, oldCookie)
        XCTAssertNotEqual(next.unsafeJavascriptSessionUUID, oldJavascript)
    }

    func testReassociationMintsJavascriptIdInsteadOfAdoptingClientValue() {
        let sessions = manager(.window)
        guard let session = sessions.get(nil, nil) else { return XCTFail() }
        let oldJavascript = session.unsafeJavascriptSessionUUID
        session._beAllowReassociation()

        let chosenJavascript = attackerUUID()
        let result = sessions.reassociate(cookieSessionUUID: nil, oldJavascript, chosenJavascript)
        XCTAssertTrue(result === session)
        XCTAssertNotEqual(session.unsafeJavascriptSessionUUID, chosenJavascript)
        XCTAssertNotEqual(session.unsafeJavascriptSessionUUID, oldJavascript)
        XCTAssertNotNil(UserSessionManager<UserSession>.validated(session.unsafeJavascriptSessionUUID))

        // the chosen value does not lead anywhere, and the old one no longer does either
        XCTAssertFalse(sessions.get(nil, chosenJavascript) === session)
        XCTAssertFalse(sessions.get(nil, oldJavascript) === session)
        XCTAssertTrue(sessions.get(session.unsafeCookieSessionUUID, session.unsafeJavascriptSessionUUID) === session)
    }

    func testReassociationIsStillOneShot() {
        let sessions = manager(.window)
        guard let session = sessions.get(nil, nil) else { return XCTFail() }
        let javascript = session.unsafeJavascriptSessionUUID
        session._beAllowReassociation()

        XCTAssertTrue(sessions.reassociate(cookieSessionUUID: nil, javascript, javascript) === session)
        XCTAssertNil(sessions.reassociate(cookieSessionUUID: nil, javascript, javascript))
    }

    func testReassociationWithoutPermissionFails() {
        let sessions = manager(.window)
        guard let session = sessions.get(nil, nil) else { return XCTFail() }
        let javascript = session.unsafeJavascriptSessionUUID
        XCTAssertNil(sessions.reassociate(cookieSessionUUID: attackerUUID(), javascript, attackerUUID()))
        XCTAssertFalse(sessions.get(attackerUUID(), javascript) === session)
    }

    func testReassociationDoesNotAdoptUnknownCookie() {
        let sessions = manager(.window)
        guard let session = sessions.get(nil, nil) else { return XCTFail() }
        session._beAllowReassociation()

        let chosenCookie = attackerUUID()
        let result = sessions.get(chosenCookie, session.unsafeJavascriptSessionUUID)
        XCTAssertTrue(result === session)
        XCTAssertNotEqual(session.unsafeCookieSessionUUID, chosenCookie)
    }
}
