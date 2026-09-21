import XCTest
import Hitch
import Flynn
import Spanker

import Picaroon

var sharedBrowser: CDPBrowser?

func getSharedBrowser() -> CDPBrowser {
    if let sharedBrowser = sharedBrowser {
        return sharedBrowser
    }
    sharedBrowser = CDPBrowser(host: "127.0.0.1",
                               port: 9222,
                               disposeOnDetach: true,
                               debug: true)
    
    sharedBrowser!.beConnect(Flynn.any) { error in
        XCTAssertNil(error)
    }
    
    return sharedBrowser!
}

final class PicaroonCDPTests: XCTestCase {
        
    func testConnectsToBrowserEndpoint() throws {
        let expectation = XCTestExpectation(description: #function)
        let browser = getSharedBrowser()
        
        browser.beNewWindow(Flynn.any) { webviewUUID, error in
            XCTAssertNotNil(webviewUUID)
            XCTAssertNil(error)
            
            print(webviewUUID!)
            
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 60)
    }
    
    func testLoadURLInNewWindow() throws {
        let expectation = XCTestExpectation(description: #function)
        let browser = getSharedBrowser()
        
        browser.beNewWindow(Flynn.any) { webviewUUID, error in
            XCTAssertNil(error)
            XCTAssertNotNil(webviewUUID)
            
            browser.beLoadURL(webviewUUID: webviewUUID!,
                              url: "https://www.apple.com",
                              until: nil,
                              timeout: nil,
                              referrer: nil,
                              Flynn.any) { error in
                XCTAssertNil(error)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 20)
    }
    
    func testEvaluateInNewWindow() throws {
        let expectation = XCTestExpectation(description: #function)
        let browser = getSharedBrowser()
        
        browser.beNewWindow(Flynn.any) { webviewUUID, error in
            XCTAssertNil(error)
            XCTAssertNotNil(webviewUUID)
            
            browser.beEvaluate(webviewUUID: webviewUUID!,
                               script: "6 * 7",
                               until: nil,
                               timeout: nil,
                               Flynn.any) { result, error in
                XCTAssertNil(error, "\(error ?? "")")
                XCTAssertEqual(result?.toInt(), 42)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 20)
    }
    
    
    func testBrowserContextsAreIsolated() throws {
        let expectation = XCTestExpectation(description: #function)
        let browser = getSharedBrowser()

        let group = DispatchGroup()
        
        group.enter()
        browser.beNewWindow(Flynn.any) { webviewUUID, error in
            browser.beLoadURL(webviewUUID: webviewUUID!,
                              url: "https://www.apple.com",
                              until: nil,
                              timeout: nil,
                              referrer: nil,
                              Flynn.any) { error in
                browser.beEvaluate(webviewUUID: webviewUUID!,
                                   script: "localStorage.setItem('who', 'first');",
                                   until: nil,
                                   timeout: nil,
                                   Flynn.any) { result, error in
                    XCTAssertEqual(result, nil)
                }
                
                browser.beEvaluate(webviewUUID: webviewUUID!,
                                   script: "localStorage.getItem('who')",
                                   until: nil,
                                   timeout: nil,
                                   Flynn.any) { result, error in
                    XCTAssertEqual(result, "first")
                    group.leave()
                }
            }
        }
        
        group.enter()
        browser.beNewWindow(Flynn.any) { webviewUUID, error in
            browser.beLoadURL(webviewUUID: webviewUUID!,
                              url: "https://www.apple.com",
                              until: nil,
                              timeout: nil,
                              referrer: nil,
                              Flynn.any) { error in
                browser.beEvaluate(webviewUUID: webviewUUID!,
                                   script: "localStorage.getItem('who')",
                                   until: nil,
                                   timeout: nil,
                                   Flynn.any) { result, error in
                    XCTAssertEqual(result, "null")
                    group.leave()
                }
            }
        }
        
        group.notify(actor: Flynn.any) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 20)
    }
    
    func testCloseWindow() throws {
        let expectation = XCTestExpectation(description: #function)
        let browser = getSharedBrowser()
        
        browser.beNewWindow(Flynn.any) { webviewUUID, error in
            XCTAssertNil(error)
            browser.beCloseWindow(webviewUUID: webviewUUID!,
                                  Flynn.any) { error in
                XCTAssertNil(error)
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 20)
    }
    
    func testManyWindowsDoNotCrossTalk() throws {
        let expectation = XCTestExpectation(description: #function)
        let browser = getSharedBrowser()

        let group = DispatchGroup()
        var webviewUUIDs: [String] = []
        
        for _ in 0..<4 {
            group.enter()
            browser.beNewWindow(Flynn.any) { webviewUUID, error in
                XCTAssertNil(error)
                webviewUUIDs.append(webviewUUID!)
                group.leave()
            }
        }
        
        group.notify(actor: Flynn.any) {
            for (index, webviewUUID) in webviewUUIDs.enumerated() {
                group.enter()
                browser.beEvaluate(webviewUUID: webviewUUID,
                                   script: "\(index) * 111",
                                   until: nil,
                                   timeout: nil,
                                   Flynn.any) { result, error in
                    XCTAssertEqual(result, "{0}" <<< [index * 111])
                    group.leave()
                }
            }
            
            group.notify(actor: Flynn.any) {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 60)
    }
    
    func testUnknownMethodReportsError() throws {
        let expectation = XCTestExpectation(description: #function)
        let browser = getSharedBrowser()

        browser.beNewWindow(Flynn.any) { webviewUUID, error in
            XCTAssertNil(error)
            browser.beSend(method: "Picaroon.notARealMethod",
                           sessionId: nil,
                           params: nil,
                           resultPath: nil,
                           Flynn.any) { result, resultJson, error in
                XCTAssertNil(result)
                XCTAssertNotNil(error)
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 60)
    }
    
    func testLargeResponseFromChrome() throws {
        let expectation = XCTestExpectation(description: #function)
        let browser = getSharedBrowser()

        browser.beNewWindow(Flynn.any) { webviewUUID, error in
            XCTAssertNil(error)
            
            let size = 4 * 1024 * 1024
            browser.beEvaluate(webviewUUID: webviewUUID!,
                               script: "'x'.repeat(\(size))",
                               until: nil,
                               timeout: nil,
                               Flynn.any) { result, error in
                XCTAssertNil(error)
                XCTAssertEqual(result?.count, size)
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 60)
    }
    
    func testCookies() throws {
        let expectation = XCTestExpectation(description: #function)
        let browser = getSharedBrowser()

        let cookies = #"{"cookies":[{"domain":".example.com","expires":1801369867,"httpOnly":false,"name":"session-id","path":"/","secure":true,"value":"000-0000000-0000000"}]}"#
        
        browser.beNewWindow(Flynn.any) { webviewUUID, error in
            XCTAssertNil(error)
            
            browser.beSetCookies(webviewUUID: webviewUUID!,
                                 cookiesJson: cookies,
                                 Flynn.any) { error in
                XCTAssertNil(error)
            }.then().doGetCookies(webviewUUID: webviewUUID!,
                                  Flynn.any) { cookies, error in
                XCTAssertNil(error)
                XCTAssertEqual(cookies?.contains("000-0000000-0000000"), true)
            }.then().doClearCookies(webviewUUID: webviewUUID!,
                                    Flynn.any) { error in
                XCTAssertNil(error)
            }.then().doGetCookies(webviewUUID: webviewUUID!,
                                  Flynn.any) { cookies, error in
                XCTAssertNil(error)
                XCTAssertEqual(cookies?.contains("000-0000000-0000000"), false)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 60)
    }
    
    func testAlertHandling() throws {
        let expectation = XCTestExpectation(description: #function)
        let browser = getSharedBrowser()
        
        browser.beNewWindow(Flynn.any) { webviewUUID, error in
            XCTAssertNil(error)
            
            browser.beEvaluate(webviewUUID: webviewUUID!,
                               script: "alert('hello world')",
                               until: nil,
                               timeout: nil,
                               Flynn.any) { result, error in
                XCTAssertNil(error)

            }.then().doEvaluate(webviewUUID: webviewUUID!,
                                script: "1+1",
                                until: nil,
                                timeout: nil,
                                Flynn.any) { result, error in
                XCTAssertNil(error)
                XCTAssertEqual(result, "2")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 60)
    }
    
    func testUserAgent() throws {
        let expectation = XCTestExpectation(description: #function)
        let browser = getSharedBrowser()
        
        let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.6.1 Safari/605.1.15"
        
        browser.beNewWindow(Flynn.any) { webviewUUID, error in
            XCTAssertNil(error)
            
            browser.beConfigure(webviewUUID: webviewUUID!,
                                userAgent: userAgent,
                                Flynn.any) { error in
                XCTAssertNil(error)
            }.then().doEvaluate(webviewUUID: webviewUUID!,
                                script: "navigator.userAgent",
                                until: nil,
                                timeout: nil,
                                Flynn.any) { result, error in
                XCTAssertNil(error)
                XCTAssertEqual(result?.toString(), userAgent)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 60)
    }
    
    func testOnPageLoadScript() throws {
        let expectation = XCTestExpectation(description: #function)
        let browser = getSharedBrowser()
        
        browser.beNewWindow(Flynn.any) { webviewUUID, error in
            XCTAssertNil(error)
            XCTAssertNotNil(webviewUUID)
            
            browser.beConfigure(webviewUUID: webviewUUID!,
                                onPageLoadScript: "window.kjhgbdf = 42;",
                                Flynn.any) { error in
                XCTAssertNil(error)
            }.then().doLoadURL(webviewUUID: webviewUUID!,
                               url: "https://www.apple.com",
                               until: nil,
                               timeout: nil,
                               referrer: nil,
                               Flynn.any) { error in
                XCTAssertNil(error)
            }.then().doEvaluate(webviewUUID: webviewUUID!,
                                script: "window.kjhgbdf",
                                until: nil,
                                timeout: nil,
                                Flynn.any) { result, error in
                XCTAssertNil(error)
                XCTAssertEqual(result?.toString(), "42")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 20)
    }
    
    func testScreenshot() throws {
        let expectation = XCTestExpectation(description: #function)
        let browser = getSharedBrowser()
        
        browser.beNewWindow(Flynn.any) { webviewUUID, error in
            XCTAssertNil(error)
            XCTAssertNotNil(webviewUUID)
            
            browser.beLoadURL(webviewUUID: webviewUUID!,
                              url: "https://www.apple.com",
                              until: nil,
                              timeout: nil,
                              referrer: nil,
                              Flynn.any) { error in
                XCTAssertNil(error)
            }.then().doScreenshot(webviewUUID: webviewUUID!,
                                  Flynn.any) { result, error in
                XCTAssertNil(error)
                XCTAssertNotNil(result)

                if let result = result,
                   let data = result.base64Decoded() {
                    try? data.write(to: URL(fileURLWithPath: "/tmp/screenshot.jpg"), options: .atomic)
                }
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 20)
    }
}
