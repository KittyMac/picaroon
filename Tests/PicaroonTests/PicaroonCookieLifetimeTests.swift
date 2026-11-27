import XCTest
import Hitch
import Flynn

@testable import Picaroon

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class PicaroonCookieLifetimeTests: XCTestCase {

    private let day: TimeInterval = 60 * 60 * 24

    private func maxAge(_ config: ServerConfig, _ userSession: UserSession) -> String? {
        let baked = Hitch()
        HttpResponse(text: "x").process(config: config, hitch: baked, socket: nil, userSession: userSession)
        guard let line = baked.toString().components(separatedBy: "\r\n").first(where: { $0.hasPrefix("Set-Cookie:") }),
              let range = line.range(of: "Max-Age=") else { return nil }
        return String(line[range.upperBound...].prefix(while: { $0.isNumber }))
    }

    func testMaxAgeFollowsSessionsOwnTimeout() {
        let config = ServerConfig(address: "127.0.0.1", port: 0)
        let sessions = UserSessionManager<UserSession>(config: config)
        let session = sessions.get(nil, nil)!
        XCTAssertEqual(maxAge(config, session), "3600")

        // the application extends the session after login
        session.safeSessionActivityTimeout = day
        XCTAssertEqual(maxAge(config, session), "86400")
    }

    func testShortSessionDoesNotShortenSharedCookie() {
        // .window: a page reload creates a throwaway 1 hour session sharing the logged in tab's cookie.
        // Its response must not cut the shared cookie down to 1 hour.
        let config = ServerConfig(address: "127.0.0.1", port: 0, sessionPer: .window)
        let sessions = UserSessionManager<UserSession>(config: config)
        let loggedInTab = sessions.get(nil, nil)!
        loggedInTab.safeSessionActivityTimeout = day

        let throwaway = sessions.get(loggedInTab.unsafeCookieSessionUUID, nil)!
        XCTAssertEqual(throwaway.unsafeCookieSessionUUID, loggedInTab.unsafeCookieSessionUUID)
        XCTAssertEqual(maxAge(config, throwaway), "86400")

        // another browser (different cookie) is unaffected
        let otherBrowser = sessions.get(nil, nil)!
        XCTAssertEqual(maxAge(config, otherBrowser), "3600")
    }

    func testCookieLifetimeShrinksWhenLongSessionGoesAway() {
        let config = ServerConfig(address: "127.0.0.1", port: 0, sessionPer: .window)
        let sessions = UserSessionManager<UserSession>(config: config)
        let loggedInTab = sessions.get(nil, nil)!
        loggedInTab.safeSessionActivityTimeout = day
        let otherTab = sessions.get(loggedInTab.unsafeCookieSessionUUID, nil)!
        XCTAssertEqual(maxAge(config, otherTab), "86400")

        sessions.end(loggedInTab)
        XCTAssertEqual(maxAge(config, otherTab), "3600")
    }

    func testLoggedInTabSurvivesReloadOverHttp() {
        // log in (24 hours), then reload the page: the navigation is answered by a throwaway session, and
        // the Set-Cookie on that response must keep the 24 hour lifetime
        let expectation = XCTestExpectation(description: #function)
        let port = Int.random(in: 8000..<65500)
        let webserver = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port)
        let baseUrl = "http://127.0.0.1:\(port)/"

        func maxAge(_ response: HTTPURLResponse?) -> String? {
            guard let response = response else { return nil }
            for (key, value) in response.allHeaderFields {
                guard (key as? String)?.lowercased() == "set-cookie",
                      let value = value as? String,
                      let range = value.range(of: "Max-Age=") else { continue }
                return String(value[range.upperBound...].prefix(while: { $0.isNumber }))
            }
            return nil
        }

        let tab = PicaroonTesting.WebView()
        tab.load(url: baseUrl) { _, response, _ in
            XCTAssertEqual(maxAge(response), "3600")

            tab.ajax(payload: #"{"service":"Server_Login"}"#) { _, response, _ in
                XCTAssertEqual(maxAge(response), "86400")
                let actor = tab.serverActorSessionUUID

                tab.load(url: baseUrl) { _, response, _ in
                    XCTAssertEqual(webserver.numberOfUserSessions(), 2)
                    XCTAssertEqual(maxAge(response), "86400")

                    tab.ajax(payload: #"{"service":"Server_GetSettings"}"#) { _, response, _ in
                        XCTAssertEqual(tab.serverActorSessionUUID, actor)
                        XCTAssertEqual(maxAge(response), "86400")
                        expectation.fulfill()
                    }
                }
            }
        }
        wait(for: [expectation], timeout: 30)
    }
}
