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
                         disposeOnDetach: true)
    
    sharedBrowser!.beConnect(Flynn.any) { error in
        XCTAssertNil(error)
    }
    
    return sharedBrowser!
}

final class PicaroonCDPTests: XCTestCase {
        
    func testConnectsToBrowserEndpoint() throws {
        let expectation = XCTestExpectation(description: #function)
        let browser = getSharedBrowser()
        
        browser.beNewWindow(Flynn.any) { windowUUID, error in
            XCTAssertNotNil(windowUUID)
            XCTAssertNil(error)
            
            print(windowUUID!)
            
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 60)
    }
    
    func testLoadURLInNewWindow() throws {
        let expectation = XCTestExpectation(description: #function)
        let browser = getSharedBrowser()
        
        browser.beNewWindow(Flynn.any) { windowUUID, error in
            XCTAssertNil(error)
            XCTAssertNotNil(windowUUID)
            
            browser.beLoadURL(webviewUUID: windowUUID!,
                              url: "https://www.apple.com",
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
        
        browser.beNewWindow(Flynn.any) { windowUUID, error in
            XCTAssertNil(error)
            XCTAssertNotNil(windowUUID)
            
            browser.beEvaluate(webviewUUID: windowUUID!,
                               script: "6 * 7",
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
        browser.beNewWindow(Flynn.any) { windowUUID, error in
            browser.beLoadURL(webviewUUID: windowUUID!,
                              url: "https://www.apple.com",
                              referrer: nil,
                              Flynn.any) { error in
                browser.beEvaluate(webviewUUID: windowUUID!,
                                   script: "localStorage.setItem('who', 'first');",
                                   Flynn.any) { result, error in
                    XCTAssertEqual(result, nil)
                }
                
                browser.beEvaluate(webviewUUID: windowUUID!,
                                   script: "localStorage.getItem('who')",
                                   Flynn.any) { result, error in
                    XCTAssertEqual(result, "first")
                    group.leave()
                }
            }
        }
        
        group.enter()
        browser.beNewWindow(Flynn.any) { windowUUID, error in
            browser.beLoadURL(webviewUUID: windowUUID!,
                              url: "https://www.apple.com",
                              referrer: nil,
                              Flynn.any) { error in
                browser.beEvaluate(webviewUUID: windowUUID!,
                                   script: "localStorage.getItem('who')",
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
        
        browser.beNewWindow(Flynn.any) { windowUUID, error in
            XCTAssertNil(error)
            browser.beCloseWindow(webviewUUID: windowUUID!,
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
        var windowUUIDs: [String] = []
        
        for _ in 0..<4 {
            group.enter()
            browser.beNewWindow(Flynn.any) { windowUUID, error in
                XCTAssertNil(error)
                windowUUIDs.append(windowUUID!)
                group.leave()
            }
        }
        
        group.notify(actor: Flynn.any) {
            for (index, windowUUID) in windowUUIDs.enumerated() {
                group.enter()
                browser.beEvaluate(webviewUUID: windowUUID,
                                   script: "\(index) * 111",
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

        browser.beNewWindow(Flynn.any) { windowUUID, error in
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

        browser.beNewWindow(Flynn.any) { windowUUID, error in
            XCTAssertNil(error)
            
            let size = 4 * 1024 * 1024
            browser.beEvaluate(webviewUUID: windowUUID!,
                               script: "'x'.repeat(\(size))",
                               Flynn.any) { result, error in
                XCTAssertNil(error)
                XCTAssertEqual(result?.count, size)
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 60)
    }
}
