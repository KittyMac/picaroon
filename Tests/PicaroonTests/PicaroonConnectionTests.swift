import XCTest
import Hitch
import Flynn

import Picaroon

final class picaroonConnectionTests: XCTestCase {
    
    private func test(_ iterations: Int,
                      _ functionName: String,
                      _ leftString: () -> (),
                      _ rightString: () -> ()) -> Bool {
        
        let leftStart = Date()
        for _ in 0..<iterations {
            leftString()
        }
        let leftTime = abs(leftStart.timeIntervalSinceNow / Double(iterations))
        
        let rightStart = Date()
        for _ in 0..<iterations {
            rightString()
        }
        let rightTime = abs(rightStart.timeIntervalSinceNow / Double(iterations))
        
        if rightTime < leftTime {
            print("\(functionName) is \(leftTime/rightTime)x faster in (right)" )
        } else {
            print("\(functionName) is \(rightTime/leftTime)x slower in (right)" )
        }
                
        return rightTime < leftTime
    }
    
    
    
    func testNTPResolver0() {
        NTP.warm()
        let correctedDate = NTP.date()
        XCTAssertTrue(abs(correctedDate.timeIntervalSinceNow) < 5.0)
    }
    
    func testIPAddress() {
        XCTAssertEqual(DNS.localIPAddress(), "192.168.111.116")
    }
    
    func testDNSResolver0() {
        let expectation = XCTestExpectation(description: "success")
        
        DNS.shared.beResolve(domain: "www.swift-linux.com", Flynn.any) { results in
            XCTAssertEqual(results.addresses.joined(), "108.236.194.50")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2)
    }
        
    func testDNSResolver1() {
        let expectation = XCTestExpectation(description: "success")
        
        DNS.shared.beResolve(domain: "www.smallplanet.com", Flynn.any) { results in
            XCTAssertTrue(results.addresses.contains("34.111.179.208"))
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testDNSResolver2() {
        let expectation = XCTestExpectation(description: "success")
        
        DNS.shared.beResolve(domain: "staging.rover.smallplanet.com", Flynn.any) { results in
            XCTAssertEqual(results.aliases.count >= 1, true)
            XCTAssertEqual(results.addresses.count, 8)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testSimpleStaticResponse() {
        let expectation = XCTestExpectation(description: "success")
        
        let port = Int.random(in: 8000..<65500)
        
        let _ = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port)
        
        let webview = PicaroonTesting.WebView()
        let baseUrl = "http://127.0.0.1:\(port)/"
        
        // Initial page load will generate a UserSession on thes server and send us back a cookie sessionUUID
        webview.load(url: baseUrl) { data, response, error in
            XCTAssertNil(error)
            XCTAssertNotNil(data)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testSimpleStaticResponseCustomBasePath() {
        let expectation = XCTestExpectation(description: "success")
        
        let port = Int.random(in: 8000..<65500)
                
        let _ = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port, basePath: "/chibley")
        
        let webview = PicaroonTesting.WebView()
        let baseUrl = "http://127.0.0.1:\(port)/chibley/"
        
        // Initial page load will generate a UserSession on thes server and send us back a cookie sessionUUID
        webview.load(url: baseUrl) { data, response, error in
            XCTAssertNil(error)
            XCTAssertNotNil(data)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2)
    }
        
    func testSimpleConnectionPersistance() {
        let expectation = XCTestExpectation(description: "success")
        
        let port = Int.random(in: 8000..<65500)
        
        let webserver = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port)
        
        let webview = PicaroonTesting.WebView()
        let baseUrl = "http://127.0.0.1:\(port)/"
        
        // Initial page load will generate a UserSession on thes server and send us back a cookie sessionUUID
        webview.load(url: baseUrl) { data, response, error in
            webview.ajax(payload: #"{"service":"Server_GetPedia","language":"en"}"#, nil)
            webview.ajax(payload: #"{"service":"Server_GetSettings"}"#) { data, response, error in
                XCTAssertEqual(webserver.numberOfUserSessions(), 1)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testMultipleConnectionPersistance() {
        let expectation = XCTestExpectation(description: "success")
        
        let port = Int.random(in: 8000..<65500)
        
        let webserver = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port)
        
        let testConnection: () -> () = {
            let webview = PicaroonTesting.WebView()
            let baseUrl = "http://127.0.0.1:\(port)/"
            
            // Initial page load will generate a UserSession on thes server and send us back a cookie sessionUUID
            webview.load(url: baseUrl) { data, response, error in
                webview.ajax(payload: #"{"service":"Server_GetPedia","language":"en"}"#, nil)
                webview.ajax(payload: #"{"service":"Server_GetSettings"}"#) { data, response, error in
                    XCTAssertEqual(webserver.numberOfUserSessions(), 3)
                    expectation.fulfill()
                }
            }
        }
        
        testConnection()
        testConnection()
        testConnection()
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testConnectionReassociation() {
        // Same browser loses its cookie (third party login round trip) and comes back with the token.
        // It still sends its stale Session-Id header, which must not matter.
        let expectation = XCTestExpectation(description: "success")
        
        let port = Int.random(in: 8000..<65500)
        
        let webserver = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port)
        
        let webview1 = PicaroonTesting.WebView()
        let baseUrl = "http://127.0.0.1:\(port)/"
        
        webview1.load(url: baseUrl) { data, response, error in
            XCTAssertNil(error)
            let oldJavascriptSessionUUID = webview1.javascriptSessionUUID
            
            webview1.ajax(payload: #"{"service":"Server_GetSettings"}"#) { data, response, error in
                XCTAssertNil(error)
                let firstActorSessionUUID = webview1.serverActorSessionUUID
                
                webview1.ajax(payload: #"{"service":"Server_AllowReassociation"}"#) { data, response, error in
                    XCTAssertNil(error)
                    guard let data = data, let token = String(data: data, encoding: .utf8) else { return XCTFail() }
                    XCTAssertNotEqual(token, oldJavascriptSessionUUID)
                    
                    webview1.clearCookies()
                    
                    webview1.load(url: baseUrl + "?sid=\(token)") { data, response, error in
                        XCTAssertNil(error)
                        // reassociation rotated the javascript session UUID
                        XCTAssertNotEqual(webview1.javascriptSessionUUID, oldJavascriptSessionUUID)
                        
                        // follow up ajax goes to the same url (sid now spent) and must still find the session
                        webview1.ajax(payload: #"{"service":"Server_GetSettings"}"#) { data, response, error in
                            XCTAssertNil(error)
                            XCTAssertEqual(webserver.numberOfUserSessions(), 1)
                            XCTAssertEqual(firstActorSessionUUID, webview1.serverActorSessionUUID)
                            expectation.fulfill()
                        }
                    }
                }
            }
        }
        
        wait(for: [expectation], timeout: 30)
    }
    
    func testConnectionReassociationBySidInUrl() {
        let expectation = XCTestExpectation(description: "success")
        
        let port = Int.random(in: 8000..<65500)
        
        let webserver = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port)
        
        let webview1 = PicaroonTesting.WebView()
        let baseUrl = "http://127.0.0.1:\(port)/"
        
        webview1.load(url: baseUrl) { data, response, error in
            XCTAssertNil(error)
            webview1.ajax(payload: #"{"service":"Server_GetSettings"}"#) { data, response, error in
                let firstActorSessionUUID = webview1.serverActorSessionUUID
                
                webview1.ajax(payload: #"{"service":"Server_AllowReassociation"}"#) { data, response, error in
                    XCTAssertNil(error)
                    guard let data = data, let token = String(data: data, encoding: .utf8) else { return XCTFail() }
                    
                    let webview2 = PicaroonTesting.WebView()
                    webview2.load(url: baseUrl + "?sid=\(token)") { data, response, error in
                        XCTAssertNil(error)
                        XCTAssertNotNil(webview2.javascriptSessionUUID)
                        
                        webview2.ajax(payload: #"{"service":"Server_GetSettings"}"#) { data, response, error in
                            XCTAssertNil(error)
                            XCTAssertEqual(webserver.numberOfUserSessions(), 1)
                            XCTAssertEqual(firstActorSessionUUID, webview2.serverActorSessionUUID)
                            expectation.fulfill()
                        }
                    }
                }
            }
        }
        
        wait(for: [expectation], timeout: 30)
    }
    
    func testConnectionReassociationRejectsSessionIdInUrl() {
        // An attacker who knows the victim's javascript session UUID, even while the victim has an
        // outstanding token, gets their own fresh session.
        let expectation = XCTestExpectation(description: "success")
        
        let port = Int.random(in: 8000..<65500)
        
        let webserver = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port)
        
        let victim = PicaroonTesting.WebView()
        let baseUrl = "http://127.0.0.1:\(port)/"
        
        victim.load(url: baseUrl) { data, response, error in
            victim.ajax(payload: #"{"service":"Server_GetSettings"}"#) { data, response, error in
                let victimActorSessionUUID = victim.serverActorSessionUUID
                
                victim.ajax(payload: #"{"service":"Server_AllowReassociation"}"#) { data, response, error in
                    let attacker = PicaroonTesting.WebView()
                    let leaked = victim.javascriptSessionUUID ?? "unknown"
                    attacker.load(url: baseUrl + "?sid=\(leaked)") { data, response, error in
                        XCTAssertNotEqual(attacker.javascriptSessionUUID, leaked)
                        
                        attacker.ajax(payload: #"{"service":"Server_GetSettings"}"#) { data, response, error in
                            XCTAssertNotEqual(victimActorSessionUUID, attacker.serverActorSessionUUID)
                            XCTAssertEqual(webserver.numberOfUserSessions(), 2)
                            expectation.fulfill()
                        }
                    }
                }
            }
        }
        
        wait(for: [expectation], timeout: 30)
    }
    
    func testConnectionReassociationTokenIsSingleUse() {
        let expectation = XCTestExpectation(description: "success")
        
        let port = Int.random(in: 8000..<65500)
        
        let webserver = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port)
        
        let webview1 = PicaroonTesting.WebView()
        let baseUrl = "http://127.0.0.1:\(port)/"
        
        webview1.load(url: baseUrl) { data, response, error in
            webview1.ajax(payload: #"{"service":"Server_GetSettings"}"#) { data, response, error in
                let firstActorSessionUUID = webview1.serverActorSessionUUID
                
                webview1.ajax(payload: #"{"service":"Server_AllowReassociation"}"#) { data, response, error in
                    guard let data = data, let token = String(data: data, encoding: .utf8) else { return XCTFail() }
                    
                    let webview2 = PicaroonTesting.WebView()
                    webview2.load(url: baseUrl + "?sid=\(token)") { data, response, error in
                        
                        // replaying the same url (log, Referer, history) gets nothing
                        let webview3 = PicaroonTesting.WebView()
                        webview3.load(url: baseUrl + "?sid=\(token)") { data, response, error in
                            XCTAssertNil(error)
                            
                            webview3.ajax(payload: #"{"service":"Server_GetSettings"}"#) { data, response, error in
                                XCTAssertNotEqual(firstActorSessionUUID, webview3.serverActorSessionUUID)
                                XCTAssertEqual(webserver.numberOfUserSessions(), 2)
                                expectation.fulfill()
                            }
                        }
                    }
                }
            }
        }
        
        wait(for: [expectation], timeout: 30)
    }
        
    /*
    func testArrayAccessPerformance() {
        let hitch = Hitch(string: "This is some sample data!")
        guard let raw = hitch.mutableRaw() else { return XCTFail() }
        
        XCTAssert(
            test (1000000, "array access",
            {
                for i in 0..<hitch.count {
                    raw[i] = raw[i] &+ 1
                }
            }, {
                for i in 0..<hitch.count {
                    (raw+i).pointee = (raw+i).pointee &+ 1
                }
            })
        )
    }
    
    func testLargeDownloadSpeeds() {
        let expectation = XCTestExpectation(description: "success")
        
        let port = 8080
        
        let _ = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port)
        
        
        wait(for: [expectation], timeout: 6000)
    }
    */
}
