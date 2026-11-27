import XCTest
import Hitch
import Flynn

@testable import Picaroon

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class PicaroonAccessTokenTests: XCTestCase {

    private func manager(_ sessionPer: UserSessionPer = .window) -> UserSessionManager<UserSession> {
        return UserSessionManager<UserSession>(config: ServerConfig(address: "127.0.0.1", port: 0, sessionPer: sessionPer))
    }

    // MARK: - Manager rules

    func testRoutesWithOwnCookieWithoutRotating() {
        let sessions = manager()
        let session = sessions.get(nil, nil)!
        let cookie = session.unsafeCookieSessionUUID
        let javascript = session.unsafeJavascriptSessionUUID
        guard let token = session.unsafeIssueAccessToken() else { return XCTFail() }

        XCTAssertNotEqual(token, cookie)
        XCTAssertNotEqual(token, javascript)
        XCTAssertTrue(sessions.access(accessToken: token, cookieSessionUUID: cookie) === session)
        XCTAssertEqual(session.unsafeCookieSessionUUID, cookie)
        XCTAssertEqual(session.unsafeJavascriptSessionUUID, javascript)
        XCTAssertTrue(sessions.get(cookie, javascript) === session)
    }

    func testRequiresSessionsOwnCookie() {
        let sessions = manager()
        let session = sessions.get(nil, nil)!
        let otherBrowser = sessions.get(nil, nil)!
        guard let token = session.unsafeIssueAccessToken(singleUse: true) else { return XCTFail() }

        XCTAssertNil(sessions.access(accessToken: token, cookieSessionUUID: nil))
        XCTAssertNil(sessions.access(accessToken: token, cookieSessionUUID: UUID().uuidHitch))
        XCTAssertNil(sessions.access(accessToken: token, cookieSessionUUID: otherBrowser.unsafeCookieSessionUUID))
        XCTAssertNil(sessions.access(accessToken: token, cookieSessionUUID: "not-a-uuid"))

        // failed attempts did not burn even a single use token
        XCTAssertTrue(sessions.access(accessToken: token, cookieSessionUUID: session.unsafeCookieSessionUUID) === session)
    }

    func testOtherTabSharingTheCookieReachesTheIssuer() {
        // .window: tabs share the cookie; the token names the tab (session) which issued it
        let sessions = manager()
        let tab1 = sessions.get(nil, nil)!
        let tab2 = sessions.get(tab1.unsafeCookieSessionUUID, nil)!
        guard let token = tab2.unsafeIssueAccessToken() else { return XCTFail() }
        XCTAssertTrue(sessions.access(accessToken: token, cookieSessionUUID: tab1.unsafeCookieSessionUUID) === tab2)
    }

    func testReusableUntilExpiryByDefault() {
        let sessions = manager()
        let session = sessions.get(nil, nil)!
        let cookie = session.unsafeCookieSessionUUID
        guard let token = session.unsafeIssueAccessToken() else { return XCTFail() }
        for _ in 0..<3 {
            XCTAssertTrue(sessions.access(accessToken: token, cookieSessionUUID: cookie) === session)
        }
    }

    func testSingleUse() {
        let sessions = manager()
        let session = sessions.get(nil, nil)!
        let cookie = session.unsafeCookieSessionUUID
        guard let token = session.unsafeIssueAccessToken(singleUse: true) else { return XCTFail() }
        XCTAssertTrue(sessions.access(accessToken: token, cookieSessionUUID: cookie) === session)
        XCTAssertNil(sessions.access(accessToken: token, cookieSessionUUID: cookie))
    }

    func testExpires() {
        let sessions = manager()
        let session = sessions.get(nil, nil)!
        guard let token = session.unsafeIssueAccessToken(timeout: 0) else { return XCTFail() }
        Thread.sleep(forTimeInterval: 0.01)
        XCTAssertNil(sessions.access(accessToken: token, cookieSessionUUID: session.unsafeCookieSessionUUID))
    }

    func testTokenKindsAreNotInterchangeable() {
        let sessions = manager()
        let session = sessions.get(nil, nil)!
        let cookie = session.unsafeCookieSessionUUID
        guard let accessToken = session.unsafeIssueAccessToken() else { return XCTFail() }
        guard let reassociationToken = session.unsafeAllowReassociation() else { return XCTFail() }

        // an access token can never move a session, and a reassociation token is not an access token
        XCTAssertNil(sessions.reassociate(reassociationToken: accessToken, cookieSessionUUID: nil))
        XCTAssertNil(sessions.access(accessToken: reassociationToken, cookieSessionUUID: cookie))
        XCTAssertEqual(session.unsafeCookieSessionUUID, cookie)

        // neither attempt consumed the other kind
        XCTAssertTrue(sessions.access(accessToken: accessToken, cookieSessionUUID: cookie) === session)
        XCTAssertTrue(sessions.reassociate(reassociationToken: reassociationToken, cookieSessionUUID: nil) === session)
    }

    func testReassociationRevokesAccessTokens() {
        let sessions = manager()
        let session = sessions.get(nil, nil)!
        guard let accessToken = session.unsafeIssueAccessToken() else { return XCTFail() }
        guard let reassociationToken = session.unsafeAllowReassociation() else { return XCTFail() }
        XCTAssertTrue(sessions.reassociate(reassociationToken: reassociationToken, cookieSessionUUID: nil) === session)
        XCTAssertNil(sessions.access(accessToken: accessToken, cookieSessionUUID: session.unsafeCookieSessionUUID))
    }

    func testTokensDieWithSession() {
        let sessions = manager()
        let session = sessions.get(nil, nil)!
        let cookie = session.unsafeCookieSessionUUID
        guard let token = session.unsafeIssueAccessToken() else { return XCTFail() }
        sessions.end(session)
        XCTAssertNil(sessions.access(accessToken: token, cookieSessionUUID: cookie))
        XCTAssertNil(session.unsafeIssueAccessToken())
    }

    func testOutstandingTokensAreBounded() {
        let sessions = manager()
        let session = sessions.get(nil, nil)!
        let cookie = session.unsafeCookieSessionUUID
        let limit = UserSessionManager<UserSession>.maximumAccessTokensPerSession
        var tokens: [Hitch] = []
        for _ in 0..<(limit + 1) {
            tokens.append(session.unsafeIssueAccessToken()!)
        }
        XCTAssertNil(sessions.access(accessToken: tokens[0], cookieSessionUUID: cookie))
        XCTAssertTrue(sessions.access(accessToken: tokens[1], cookieSessionUUID: cookie) === session)
        XCTAssertTrue(sessions.access(accessToken: tokens[limit], cookieSessionUUID: cookie) === session)
    }

    // MARK: - Over http

    func testDownloadNavigationReachesTabSession() {
        let expectation = XCTestExpectation(description: #function)
        let port = Int.random(in: 8000..<65500)
        let webserver = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port)
        let baseUrl = "http://127.0.0.1:\(port)/"

        let tab = PicaroonTesting.WebView()
        tab.load(url: baseUrl) { _, _, _ in
            tab.ajax(payload: #"{"service":"Server_GetSettings"}"#) { _, _, _ in
                let actor = tab.serverActorSessionUUID
                let javascript = tab.javascriptSessionUUID

                tab.ajax(payload: #"{"service":"Server_IssueAccessToken"}"#) { data, _, _ in
                    guard let data = data, let token = String(data: data, encoding: .utf8) else { return XCTFail() }

                    // a navigation: cookie only, no Session-Id header
                    tab.load(url: baseUrl + "download/report.pdf?sid=\(token)") { _, _, _ in
                        XCTAssertEqual(tab.serverActorSessionUUID, actor)
                        XCTAssertEqual(tab.javascriptSessionUUID, javascript)

                        // and again (default tokens survive a browser re-requesting the download)
                        tab.load(url: baseUrl + "download/report.pdf?sid=\(token)") { _, _, _ in
                            XCTAssertEqual(tab.serverActorSessionUUID, actor)
                            XCTAssertEqual(webserver.numberOfUserSessions(), 1)
                            expectation.fulfill()
                        }
                    }
                }
            }
        }
        wait(for: [expectation], timeout: 30)
    }

    func testLeakedDownloadUrlIsUselessInAnotherBrowser() {
        let expectation = XCTestExpectation(description: #function)
        let port = Int.random(in: 8000..<65500)
        let webserver = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port)
        let baseUrl = "http://127.0.0.1:\(port)/"

        let victim = PicaroonTesting.WebView()
        victim.load(url: baseUrl) { _, _, _ in
            victim.ajax(payload: #"{"service":"Server_GetSettings"}"#) { _, _, _ in
                let victimActor = victim.serverActorSessionUUID

                victim.ajax(payload: #"{"service":"Server_IssueAccessToken"}"#) { data, _, _ in
                    guard let data = data, let token = String(data: data, encoding: .utf8) else { return XCTFail() }

                    let attacker = PicaroonTesting.WebView()
                    attacker.load(url: baseUrl + "download/report.pdf?sid=\(token)") { _, _, _ in
                        XCTAssertNotEqual(attacker.serverActorSessionUUID, victimActor)
                        XCTAssertEqual(webserver.numberOfUserSessions(), 2)

                        // the victim's own download still works
                        victim.load(url: baseUrl + "download/report.pdf?sid=\(token)") { _, _, _ in
                            XCTAssertEqual(victim.serverActorSessionUUID, victimActor)
                            expectation.fulfill()
                        }
                    }
                }
            }
        }
        wait(for: [expectation], timeout: 30)
    }

    func testDownloadNavigationWithoutTokenGetsFreshSession() {
        // the CSRF property still holds for downloads: the victim's cookie alone (or with the tab's
        // javascript UUID in sid, the old download scheme) never reaches the tab's session
        let expectation = XCTestExpectation(description: #function)
        let port = Int.random(in: 8000..<65500)
        let webserver = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port)
        let baseUrl = "http://127.0.0.1:\(port)/"

        let tab = PicaroonTesting.WebView()
        tab.load(url: baseUrl) { _, _, _ in
            tab.ajax(payload: #"{"service":"Server_GetSettings"}"#) { _, _, _ in
                let actor = tab.serverActorSessionUUID
                let javascript = tab.javascriptSessionUUID ?? ""

                tab.load(url: baseUrl + "download/report.pdf") { _, _, _ in
                    XCTAssertNotEqual(tab.serverActorSessionUUID, actor)

                    tab.load(url: baseUrl + "download/report.pdf?sid=\(javascript)") { _, _, _ in
                        XCTAssertNotEqual(tab.serverActorSessionUUID, actor)
                        XCTAssertEqual(webserver.numberOfUserSessions(), 3)
                        expectation.fulfill()
                    }
                }
            }
        }
        wait(for: [expectation], timeout: 30)
    }
}
