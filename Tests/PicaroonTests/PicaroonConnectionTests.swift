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
    
    #if os(macOS)
    
    func testDNSResolver0() {
        let expectation = XCTestExpectation(description: "success")
        
        DNS.shared.beResolve(domain: "www.swift-linux.com", Flynn.any) { addresses in
            XCTAssertEqual(addresses.joined(), "108.236.194.50")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testDNSResolver1() {
        let expectation = XCTestExpectation(description: "success")
        
        DNS.shared.beResolve(domain: "www.smallplanet.com", Flynn.any) { addresses in
            XCTAssertEqual(addresses.joined(separator: ","), "69.164.218.110")
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
        let expectation = XCTestExpectation(description: "success")
        
        let port = Int.random(in: 8000..<65500)
        
        let webserver = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port)
        
        let webview1 = PicaroonTesting.WebView()
        let baseUrl = "http://127.0.0.1:\(port)/"
        
        // Initial page load will generate a UserSession on thes server and send us back a cookie sessionUUID
        webview1.load(url: baseUrl) { data, response, error in
            XCTAssertNotNil(data)
            XCTAssertNil(error)
                            
            webview1.ajax(payload: #"{"service":"Server_AllowReassociation"}"#) { data, response, error in
                XCTAssertNotNil(data)
                XCTAssertNil(error)
                
                let firstActorSessionUUID = webview1.serverActorSessionUUID
                webview1.clearCookies()
                
                webview1.ajax(payload: #"{"service":"Server_GetSettings"}"#) { data, response, error in
                    XCTAssertNotNil(data)
                    XCTAssertNil(error)
                    
                    XCTAssertEqual(webserver.numberOfUserSessions(), 1)
                    XCTAssertEqual(firstActorSessionUUID, webview1.serverActorSessionUUID)

                    expectation.fulfill()
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
        
        // Initial page load will generate a UserSession on thes server and send us back a cookie sessionUUID
        webview1.load(url: baseUrl) { data, response, error in
            XCTAssertNotNil(data)
            XCTAssertNil(error)
                        
            webview1.ajax(payload: #"{"service":"Server_AllowReassociation"}"#) { data, response, error in
                XCTAssertNotNil(data)
                XCTAssertNil(error)
                
                let webview2 = PicaroonTesting.WebView()
                let sid = webview1.javascriptSessionUUID ?? "unknown"
                webview2.load(url: baseUrl + "?sid=\(sid)") { data, response, error in
                    print("1: " + (webview2.javascriptSessionUUID ?? "unknown"))
                    XCTAssertNotNil(data)
                    XCTAssertNil(error)
                                        
                    webview2.ajax(payload: #"{"service":"Server_GetSettings"}"#) { data, response, error in
                        print("3: " + (webview2.javascriptSessionUUID ?? "unknown"))
                        XCTAssertNotNil(data)
                        XCTAssertNil(error)
                        
                        XCTAssertEqual(webserver.numberOfUserSessions(), 1)
                        XCTAssertEqual(webview1.serverActorSessionUUID, webview2.serverActorSessionUUID)
                        
                        expectation.fulfill()
                    }
                }
            }
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    #endif
    
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
