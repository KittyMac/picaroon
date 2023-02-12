import XCTest
import Hitch
import Flynn

import Picaroon

final class PicaroonHttpSessionTests: XCTestCase {
    
    func testManyHttpTasksOnOneShotSession() {
        let expectation = XCTestExpectation(description: "testManyHttpTasksOnSingleSession")
        
        var waiting = 2048
        for _ in 0..<2048 {
            HTTPSession.oneshot.beRequest(url: "https://www.swift-linux.com",
                                          httpMethod: "GET",
                                          params: [:],
                                          headers: [:],
                                          cookies: nil,
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
        let expectation = XCTestExpectation(description: "testManyHttpTasksOnSingleSession")
        
        HTTPSessionManager.shared.beNew(Flynn.any) { session in
            var waiting = 2048
            for _ in 0..<2048 {
                session.beRequest(url: "https://www.swift-linux.com",
                                  httpMethod: "GET",
                                  params: [:],
                                  headers: [:],
                                  cookies: nil,
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
        let expectation = XCTestExpectation(description: "testManyHttpSessions")
        
        var waiting = 2048
        for _ in 0..<2048 {
            HTTPSessionManager.shared.beNew(Flynn.any) { session in
                session.beRequest(url: "https://www.swift-linux.com",
                                  httpMethod: "GET",
                                  params: [:],
                                  headers: [:],
                                  cookies: nil,
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
}
