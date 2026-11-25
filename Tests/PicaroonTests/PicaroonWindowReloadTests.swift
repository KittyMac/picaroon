import XCTest
import Hitch
import Flynn

@testable import Picaroon

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class PicaroonWindowReloadTests: XCTestCase {

    private func sessionIdHeader(_ response: HTTPURLResponse?) -> String? {
        guard let response = response else { return nil }
        for (key, value) in response.allHeaderFields {
            if (key as? String)?.lowercased() == "session-id" {
                return value as? String
            }
        }
        return nil
    }

    func testSessionIdHeaderInEveryMode() {
        for mode in [UserSessionPer.window, .browser, .api] {
            let config = ServerConfig(address: "127.0.0.1", port: 0, sessionPer: mode)
            let session = UserSessionManager<UserSession>(config: config).get(nil, nil)!
            let baked = Hitch()
            HttpResponse(text: "x").process(config: config, hitch: baked, socket: nil, userSession: session)
            XCTAssertTrue(baked.toString().contains("\r\nSession-Id: \(session.unsafeJavascriptSessionUUID)\r\n"), "mode \(mode)")
        }
    }

    func testReloadKeepsTabSession() {
        // A logged in tab reloads: the navigation carries only the cookie, the server hands it a throwaway
        // session, and the page keeps the Session-Id it already holds. The tab must stay on its session.
        let expectation = XCTestExpectation(description: #function)
        let port = Int.random(in: 8000..<65500)
        let webserver = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port)
        let baseUrl = "http://127.0.0.1:\(port)/"

        let tab = PicaroonTesting.WebView()
        tab.load(url: baseUrl) { _, _, _ in
            tab.ajax(payload: #"{"service":"Server_GetSettings"}"#) { _, response, _ in
                let actor = tab.serverActorSessionUUID
                let javascriptSessionUUID = tab.javascriptSessionUUID
                XCTAssertEqual(self.sessionIdHeader(response), javascriptSessionUUID)

                tab.load(url: baseUrl) { _, _, _ in
                    XCTAssertEqual(tab.javascriptSessionUUID, javascriptSessionUUID)

                    tab.ajax(payload: #"{"service":"Server_GetSettings"}"#) { _, response, _ in
                        XCTAssertEqual(tab.serverActorSessionUUID, actor)
                        XCTAssertEqual(self.sessionIdHeader(response), javascriptSessionUUID)
                        XCTAssertFalse(tab.sessionWasReplaced)
                        // the reload's throwaway session exists alongside the tab's real one
                        XCTAssertEqual(webserver.numberOfUserSessions(), 2)
                        expectation.fulfill()
                    }
                }
            }
        }
        wait(for: [expectation], timeout: 30)
    }

    func testStaleSessionIdAfterServerRestart() {
        // The tab's session is gone (here: a second server process stands in for the rebooted one).
        // The first ajax reports a replacement Session-Id; once the page adopts it (and reloads)
        // everything works again without closing the tab.
        let expectation = XCTestExpectation(description: #function)
        let port1 = Int.random(in: 8000..<36000)
        let port2 = Int.random(in: 36000..<65500)
        let before = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port1)
        let after = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port2)

        let tab = PicaroonTesting.WebView()
        tab.load(url: "http://127.0.0.1:\(port1)/") { _, _, _ in
            tab.ajax(payload: #"{"service":"Server_GetSettings"}"#) { _, _, _ in
                let staleJavascriptSessionUUID = tab.javascriptSessionUUID
                XCTAssertEqual(before.numberOfUserSessions(), 1)

                // "reboot": reload against the fresh server, still holding the stale Session-Id
                tab.load(url: "http://127.0.0.1:\(port2)/") { _, _, _ in
                    XCTAssertEqual(tab.javascriptSessionUUID, staleJavascriptSessionUUID)

                    tab.ajax(payload: #"{"service":"Server_GetSettings"}"#) { _, response, _ in
                        XCTAssertTrue(tab.sessionWasReplaced)
                        XCTAssertNotEqual(self.sessionIdHeader(response), staleJavascriptSessionUUID)
                        XCTAssertEqual(tab.javascriptSessionUUID, self.sessionIdHeader(response))
                        let recoveredActor = tab.serverActorSessionUUID

                        // the page reloads after adopting the new value; it now sticks
                        tab.sessionWasReplaced = false
                        tab.load(url: "http://127.0.0.1:\(port2)/") { _, _, _ in
                            tab.ajax(payload: #"{"service":"Server_GetSettings"}"#) { _, _, _ in
                                XCTAssertFalse(tab.sessionWasReplaced)
                                XCTAssertEqual(tab.serverActorSessionUUID, recoveredActor)
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
