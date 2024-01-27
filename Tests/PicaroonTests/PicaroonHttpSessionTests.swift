import XCTest
import Hitch
import Flynn

import Picaroon

final class PicaroonHttpSessionTests: XCTestCase {
    
    func testManyHttpTasksOnOneShotSession() {
        let expectation = XCTestExpectation(description: #function)
        var waiting = 4096
        for _ in 0..<4096 {
            HTTPSession.oneshot.beRequest(url: "https://www.swift-linux.com",
                                          httpMethod: "GET",
                                          params: [:],
                                          headers: [:],
                                          cookies: nil,
                                          timeoutRetry: nil,
                                          proxy: nil,
                                          body: nil,
                                          Flynn.any) { data, response, error in
                XCTAssertNil(error)
                XCTAssertNotNil(data)
                waiting -= 1
                
                print(waiting)
                
                if waiting <= 0 {
                    expectation.fulfill()
                }
            }
        }
        
        wait(for: [expectation], timeout: 600)
    }
    
    func testManyHttpTasksOnSingleSession() {
        let expectation = XCTestExpectation(description: #function)
        HTTPSessionManager.shared.beNew(Flynn.any) { session in
            var waiting = 4096
            for _ in 0..<4096 {
                session.beRequest(url: "https://www.swift-linux.com",
                                  httpMethod: "GET",
                                  params: [:],
                                  headers: [:],
                                  cookies: nil,
                                  timeoutRetry: nil,
                                  proxy: nil,
                                  body: nil,
                                  Flynn.any) { data, response, error in
                    XCTAssertNil(error)
                    XCTAssertNotNil(data)
                    waiting -= 1
                    
                    print(waiting)
                    
                    if waiting <= 0 {
                        expectation.fulfill()
                    }
                }
            }
        }
        
        wait(for: [expectation], timeout: 600)
    }
    
    func testManyHttpSessions() {
        let expectation = XCTestExpectation(description: #function)
        var waiting = 4096
        for _ in 0..<4096 {
            HTTPSessionManager.shared.beNew(Flynn.any) { session in
                session.beRequest(url: "https://www.swift-linux.com",
                                  httpMethod: "GET",
                                  params: [:],
                                  headers: [:],
                                  cookies: nil,
                                  timeoutRetry: nil,
                                  proxy: nil,
                                  body: nil,
                                  Flynn.any) { data, response, error in
                    XCTAssertNil(error)
                    XCTAssertNotNil(data)
                    waiting -= 1
                    
                    print(waiting)
                    
                    if waiting <= 0 {
                        expectation.fulfill()
                    }
                }
            }
        }
        
        wait(for: [expectation], timeout: 600)
    }
    
    func testNoTimeoutOnOneShotSession() {
        let expectation = XCTestExpectation(description: #function)
        var waiting = 4
        for _ in 0..<4 {
            
            let start = Date()
            HTTPSession.oneshot.beRequest(url: "https://www.swift-linux.com",
                                          httpMethod: "GET",
                                          params: [:],
                                          headers: [:],
                                          cookies: nil,
                                          timeoutRetry: nil,
                                          proxy: nil,
                                          body: nil,
                                          Flynn.any) { data, response, error in
                
                if abs(start.timeIntervalSinceNow) > 10 {
                    XCTFail("timeout occurred \(abs(start.timeIntervalSinceNow))")
                }
                
                XCTAssertNil(error)
                XCTAssertNotNil(data)
                waiting -= 1
                
                print(waiting)
                
                if waiting <= 0 {
                    expectation.fulfill()
                }
            }
        }
        
        wait(for: [expectation], timeout: 600)
    }
    
    func testNoTimeoutOnSingleSession() {
        let expectation = XCTestExpectation(description: #function)
        HTTPSessionManager.shared.beNew(Flynn.any) { session in
            var waiting = 4
            for _ in 0..<4 {
                
                let start = Date()
                session.beRequest(url: "https://www.swift-linux.com",
                                  httpMethod: "GET",
                                  params: [:],
                                  headers: [:],
                                  cookies: nil,
                                  timeoutRetry: nil,
                                  proxy: nil,
                                  body: nil,
                                  Flynn.any) { data, response, error in
                    if abs(start.timeIntervalSinceNow) > 10 {
                        XCTFail("timeout occurred")
                    }

                    XCTAssertNil(error)
                    XCTAssertNotNil(data)
                    waiting -= 1
                    
                    print(waiting)
                    
                    if waiting <= 0 {
                        expectation.fulfill()
                    }
                }
            }
        }
        
        wait(for: [expectation], timeout: 600)
    }
    
    func testNoTimeoutSessions() {
        let expectation = XCTestExpectation(description: #function)
        var waiting = 4
        for _ in 0..<4 {
            
            let start = Date()
            HTTPSessionManager.shared.beNew(Flynn.any) { session in
                session.beRequest(url: "https://www.swift-linux.com",
                                  httpMethod: "GET",
                                  params: [:],
                                  headers: [:],
                                  cookies: nil,
                                  timeoutRetry: nil,
                                  proxy: nil,
                                  body: nil,
                                  Flynn.any) { data, response, error in
                    if abs(start.timeIntervalSinceNow) > 10 {
                        XCTFail("timeout occurred")
                    }

                    XCTAssertNil(error)
                    XCTAssertNotNil(data)
                    waiting -= 1
                    
                    print(waiting)
                    
                    if waiting <= 0 {
                        expectation.fulfill()
                    }
                }
            }
        }
        
        wait(for: [expectation], timeout: 600)
    }
}
