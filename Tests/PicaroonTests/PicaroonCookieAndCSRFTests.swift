import XCTest
import Hitch
import Flynn

@testable import Picaroon

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class PicaroonCookieAndCSRFTests: XCTestCase {

    // MARK: - Helpers

    private func manager(_ config: ServerConfig) -> UserSessionManager<UserSession> {
        return UserSessionManager<UserSession>(config: config)
    }

    private func setCookieLines(_ config: ServerConfig, _ userSession: UserSession) -> [String] {
        let baked = Hitch()
        HttpResponse(text: "x").process(config: config, hitch: baked, socket: nil, userSession: userSession)
        return baked.toString()
            .components(separatedBy: "\r\n")
            .filter { $0.hasPrefix("Set-Cookie:") }
    }

    private func request(_ url: String,
                         method: String,
                         headers: [String: String],
                         body: String? = nil,
                         _ callback: @escaping (String?, HTTPURLResponse?) -> Void) {
        HTTPSessionManager.shared.beNew(Flynn.any) { session in
            session.beRequest(url: url,
                              httpMethod: method,
                              params: [:],
                              headers: headers,
                              cookies: nil,
                              timeoutRetry: nil,
                              proxy: nil,
                              body: body?.data(using: .utf8),
                              Flynn.any) { data, response, error in
                callback(data.flatMap { String(data: $0, encoding: .utf8) }, response)
            }
        }
    }

    // MARK: - Cookie attributes

    func testSecureDefaults() {
        let config = ServerConfig(address: "127.0.0.1", port: 0)
        XCTAssertTrue(config.cookieSecure)
        XCTAssertEqual(config.cookieSameSite, .lax)

        let session = manager(config).get(nil, nil)!
        let lines = setCookieLines(config, session)
        XCTAssertEqual(lines, [
            "Set-Cookie: __Host-\(Picaroon.userSessionCookie)=\(session.unsafeCookieSessionUUID); Path=/; Max-Age=3600; HttpOnly; SameSite=Lax; Secure"
        ])
    }

    func testPlainHttpDevelopmentConfig() {
        let config = ServerConfig(address: "127.0.0.1", port: 0,
                                  sessionActivityTimeout: 120,
                                  cookieSecure: false,
                                  cookieSameSite: .strict)
        let session = manager(config).get(nil, nil)!
        XCTAssertEqual(setCookieLines(config, session), [
            "Set-Cookie: \(Picaroon.userSessionCookie)=\(session.unsafeCookieSessionUUID); Path=/; Max-Age=120; HttpOnly; SameSite=Strict"
        ])
    }

    func testMaxAgeTracksActivityTimeout() {
        for (timeout, expected) in [(60.0 * 60 * 24, "86400"), (0.25, "1")] {
            let config = ServerConfig(address: "127.0.0.1", port: 0, sessionActivityTimeout: timeout)
            let session = manager(config).get(nil, nil)!
            XCTAssertTrue(setCookieLines(config, session).first?.contains("; Max-Age=\(expected);") == true)
        }
    }

    func testCookieName() {
        let base = Picaroon.userSessionCookie.toString()
        XCTAssertNotNil(UUID(uuidString: base), "base name stays a random per-process UUID")
        XCTAssertEqual(ServerConfig(address: "127.0.0.1", port: 0).sessionCookieName.toString(), "__Host-" + base)
        XCTAssertEqual(ServerConfig(address: "127.0.0.1", port: 0, cookieSecure: false).sessionCookieName.toString(), base)
    }

    func testConfigDecodesWithoutCookieKeys() throws {
        let original = ServerConfig(address: "127.0.0.1", port: 8080, cookieSecure: false, cookieSameSite: .strict)
        let encoded = try JSONEncoder().encode(original)

        // round trip keeps explicit values
        let roundTrip = try JSONDecoder().decode(ServerConfig.self, from: encoded)
        XCTAssertFalse(roundTrip.cookieSecure)
        XCTAssertEqual(roundTrip.cookieSameSite, .strict)
        XCTAssertEqual(roundTrip.port, 8080)

        // a config serialized before these settings existed decodes to the secure defaults
        var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacy.removeValue(forKey: "cookieSecure")
        legacy.removeValue(forKey: "cookieSameSite")
        let legacyConfig = try JSONDecoder().decode(ServerConfig.self,
                                                    from: try JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(legacyConfig.cookieSecure)
        XCTAssertEqual(legacyConfig.cookieSameSite, .lax)
        XCTAssertEqual(legacyConfig.basePath, original.basePath)
    }

    func testUnprefixedCookieIsIgnoredWhenSecure() {
        // With cookieSecure the server only reads the __Host- prefixed name, so a cookie planted under the
        // bare name (which a sibling subdomain or plain http could set) is ignored.
        let expectation = XCTestExpectation(description: #function)
        let port = Int.random(in: 8000..<65500)
        let webserver = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port)
        let baseUrl = "http://127.0.0.1:\(port)/"

        let secureName = "__Host-" + Picaroon.userSessionCookie.toString()
        let bareName = Picaroon.userSessionCookie.toString()

        let victim = PicaroonTesting.WebView()
        victim.load(url: baseUrl) { _, response, _ in
            XCTAssertNotNil(victim.cookies[secureName])
            XCTAssertNil(victim.cookies[bareName])

            victim.ajax(payload: #"{"service":"Server_GetSettings"}"#) { _, _, _ in
                let victimActor = victim.serverActorSessionUUID
                let cookie = victim.cookies[secureName] ?? ""

                self.request(baseUrl, method: "POST",
                             headers: ["Cookie": "\(bareName)=\(cookie)",
                                       "Session-Id": victim.javascriptSessionUUID ?? ""],
                             body: #"{"service":"Server_GetSettings"}"#) { body, _ in
                    XCTAssertNotNil(body)
                    XCTAssertNotEqual(body, victimActor)
                    XCTAssertEqual(webserver.numberOfUserSessions(), 2)
                    expectation.fulfill()
                }
            }
        }
        wait(for: [expectation], timeout: 30)
    }

    // MARK: - CSRF regression (.window mode)
    //
    // In .window mode the Session-Id header is the CSRF control: a cross-site page can make the browser
    // attach our cookie, but it cannot attach a custom header without a CORS preflight we never approve.
    // These tests pin that a cookie without the matching Session-Id never reaches an existing session.

    func testCookieAloneNeverReachesWindowSession() {
        let sessions = manager(ServerConfig(address: "127.0.0.1", port: 0, sessionPer: .window))
        let victim = sessions.get(nil, nil)!
        let cookie = victim.unsafeCookieSessionUUID

        XCTAssertFalse(sessions.get(cookie, nil) === victim)
        XCTAssertFalse(sessions.get(cookie, UUID().uuidHitch) === victim)
        XCTAssertFalse(sessions.get(cookie, "not-a-uuid") === victim)

        // the matching pair still works
        XCTAssertTrue(sessions.get(cookie, victim.unsafeJavascriptSessionUUID) === victim)
    }

    func testBrowserModeIsCookieOnly() {
        // Documents the contrast: in .browser mode the cookie alone is the credential, so CSRF protection
        // there rests on SameSite plus whatever the application adds.
        let sessions = manager(ServerConfig(address: "127.0.0.1", port: 0, sessionPer: .browser))
        let victim = sessions.get(nil, nil)!
        XCTAssertTrue(sessions.get(victim.unsafeCookieSessionUUID, nil) === victim)
    }

    func testForgedCrossSiteRequestsDoNotReachVictimSession() {
        // Simulates what a cross-site page can make a browser send: the victim's cookie, a simple
        // content type, and no Session-Id header (GET navigation, form POST, and a POST with a json body).
        let expectation = XCTestExpectation(description: #function)
        let port = Int.random(in: 8000..<65500)
        let webserver = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port)
        let baseUrl = "http://127.0.0.1:\(port)/"

        let victim = PicaroonTesting.WebView()
        victim.load(url: baseUrl) { _, _, _ in
            victim.ajax(payload: #"{"service":"Server_GetSettings"}"#) { _, _, _ in
                let victimActor = victim.serverActorSessionUUID
                let victimJavascript = victim.javascriptSessionUUID ?? ""
                let cookieName = "__Host-" + Picaroon.userSessionCookie.toString()
                let cookieHeader = "\(cookieName)=\(victim.cookies[cookieName] ?? "")"

                self.request(baseUrl, method: "POST",
                             headers: ["Cookie": cookieHeader,
                                       "Content-Type": "application/x-www-form-urlencoded"],
                             body: "service=Server_GetSettings") { formBody, _ in
                    XCTAssertNotNil(formBody)
                    XCTAssertNotEqual(formBody, victimActor)

                    self.request(baseUrl, method: "POST",
                                 headers: ["Cookie": cookieHeader,
                                           "Content-Type": "text/plain"],
                                 body: #"{"service":"Server_GetSettings"}"#) { jsonBody, _ in
                        XCTAssertNotNil(jsonBody)
                        XCTAssertNotEqual(jsonBody, victimActor)

                        self.request(baseUrl, method: "GET",
                                     headers: ["Cookie": cookieHeader]) { getBody, _ in
                            // a GET gets a bootstrap for a *new* session, never the victim's identifiers
                            XCTAssertNotNil(getBody)
                            XCTAssertFalse(getBody?.contains(victimJavascript) ?? true)

                            // the victim is untouched and still reachable with the real pair
                            victim.ajax(payload: #"{"service":"Server_GetSettings"}"#) { _, _, _ in
                                XCTAssertEqual(victim.serverActorSessionUUID, victimActor)
                                XCTAssertEqual(webserver.numberOfUserSessions(), 4)
                                expectation.fulfill()
                            }
                        }
                    }
                }
            }
        }
        wait(for: [expectation], timeout: 30)
    }
}
