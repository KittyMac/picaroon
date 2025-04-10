import XCTest
import Hitch
import Flynn

import Picaroon

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// use timeoutRetry of 0 for determining if we can reduce the initial timeouts
// set to nil for default behaviour (3x retry)
fileprivate let timeoutRetry: Int? = 3
fileprivate let maxConnection = 1024

final class PicaroonHttpSessionTests: XCTestCase {
    
    
    func testSingleHttpURLSession() {
        let expectation = XCTestExpectation(description: #function)

        let request = URLRequest(url: URL(string: "https://www.apple.com")!)
    
        URLSession.shared.dataTask(with: request) { data, response, error in
            XCTAssertNil(error)
            expectation.fulfill()
        }.resume()
    
        wait(for: [expectation], timeout: 600)
    }
    
    func testSingleHttpSession() {
        let expectation = XCTestExpectation(description: #function)
    
        HTTPSession.oneshot.beRequest(url: "https://www.apple.com",
                                      httpMethod: "GET",
                                      params: [:],
                                      headers: [:],
                                      cookies: nil,
                                      timeoutRetry: timeoutRetry,
                                      proxy: nil,
                                      body: nil,
                                      Flynn.any) { data, response, error in
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 4)
    }
    
    #if !os(Windows)
    func testManyHttpTasksBaseline() {
        let expectation = XCTestExpectation(description: #function)
        var waiting = maxConnection
        var success = 0
        var fail = 0
        
        for _ in 0..<maxConnection {
            
            let request = URLRequest(url: URL(string: "https://www.apple.com")!)
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                
                if error == nil {
                    success += 1
                } else {
                    fail += 1
                }
                
                waiting -= 1
                
                print(waiting)
                
                if waiting <= 0 {
                    expectation.fulfill()
                }
            }.resume()
        }
        
        wait(for: [expectation], timeout: 600)
        
        XCTAssertEqual(success, maxConnection)
        XCTAssertEqual(fail, 0)
        
        // apple.com: 40s
    }
    #endif
    
    func testManyHttpTasksOnOneShotSession() {
        let expectation = XCTestExpectation(description: #function)
        var waiting = maxConnection
        var success = 0
        var fail = 0

        for _ in 0..<maxConnection {
            HTTPSession.oneshot.beRequest(url: "https://www.apple.com",
                                          httpMethod: "GET",
                                          params: [:],
                                          headers: [:],
                                          cookies: nil,
                                          timeoutRetry: timeoutRetry,
                                          proxy: nil,
                                          body: nil,
                                          Flynn.any) { data, response, error in
                if error == nil {
                    success += 1
                } else {
                    fail += 1
                }

                waiting -= 1
                
                print(waiting)
                
                if waiting <= 0 {
                    expectation.fulfill()
                }
            }
        }
        
        wait(for: [expectation], timeout: 600)
        
        XCTAssertEqual(success, maxConnection)
        XCTAssertEqual(fail, 0)
        
        // apple.com: 25s
    }
    
    func testManyHttpTasksOnSingleSession() {
        let expectation = XCTestExpectation(description: #function)
        var success = 0
        var fail = 0

        HTTPSessionManager.shared.beNew(Flynn.any) { session in
            var waiting = maxConnection
            for _ in 0..<maxConnection {
                session.beRequest(url: "https://www.apple.com",
                                  httpMethod: "GET",
                                  params: [:],
                                  headers: [:],
                                  cookies: nil,
                                  timeoutRetry: timeoutRetry,
                                  proxy: nil,
                                  body: nil,
                                  Flynn.any) { data, response, error in
                    if error == nil {
                        success += 1
                    } else {
                        fail += 1
                    }

                    waiting -= 1
                    
                    print(waiting)
                    
                    if waiting <= 0 {
                        expectation.fulfill()
                    }
                }
            }
        }
        
        wait(for: [expectation], timeout: 600)
        
        XCTAssertEqual(success, maxConnection)
        XCTAssertEqual(fail, 0)
        
        // apple.com: 26s
    }
    
    func testManyHttpSessions() {
        let expectation = XCTestExpectation(description: #function)
        var waiting = maxConnection
        var success = 0
        var fail = 0

        for _ in 0..<maxConnection {
            HTTPSessionManager.shared.beNew(Flynn.any) { session in
                session.beRequest(url: "https://www.apple.com",
                                  httpMethod: "GET",
                                  params: [:],
                                  headers: [:],
                                  cookies: nil,
                                  timeoutRetry: timeoutRetry,
                                  proxy: nil,
                                  body: nil,
                                  Flynn.any) { data, response, error in
                    if error == nil {
                        success += 1
                    } else {
                        fail += 1
                    }

                    waiting -= 1
                    
                    print(waiting)
                    
                    if waiting <= 0 {
                        expectation.fulfill()
                    }
                }
            }
        }
        
        wait(for: [expectation], timeout: 600)
        
        XCTAssertEqual(success, maxConnection)
        XCTAssertEqual(fail, 0)
        
        // apple.com: 82s
    }
    
    func testNoTimeoutOnOneShotSession() {
        let expectation = XCTestExpectation(description: #function)
        var waiting = 4
        for _ in 0..<4 {
            
            let start = Date()
            HTTPSession.oneshot.beRequest(url: "https://www.apple.com",
                                          httpMethod: "GET",
                                          params: [:],
                                          headers: [:],
                                          cookies: nil,
                                          timeoutRetry: timeoutRetry,
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
                session.beRequest(url: "https://www.apple.com",
                                  httpMethod: "GET",
                                  params: [:],
                                  headers: [:],
                                  cookies: nil,
                                  timeoutRetry: timeoutRetry,
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
                session.beRequest(url: "https://www.apple.com",
                                  httpMethod: "GET",
                                  params: [:],
                                  headers: [:],
                                  cookies: nil,
                                  timeoutRetry: timeoutRetry,
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
    
    func testSynchronousRequests() {
        var waiting = 4
        for _ in 0..<4 {
            
            let start = Date()
            let (data, response, error) = HTTPSession.oneshot.unsafeSynchronousRequest(url: "https://www.apple.com",
                                                                                       httpMethod: "GET",
                                                                                       params: [:],
                                                                                       headers: [:],
                                                                                       cookies: nil,
                                                                                       timeoutRetry: timeoutRetry,
                                                                                       proxy: nil,
                                                                                       body: nil)
            if abs(start.timeIntervalSinceNow) > 10 {
                XCTFail("timeout occurred \(abs(start.timeIntervalSinceNow))")
            }
            
            XCTAssertNil(error)
            XCTAssertNotNil(response)
            XCTAssertNotNil(data)
            waiting -= 1
            
            print(waiting)
        }
    }
    
    func testAsynchronousRequests() {
        let expectation = XCTestExpectation(description: #function)
        var waiting = 4
        let lock = NSLock()
        for _ in 0..<4 {
            
            let start = Date()
            HTTPSession.oneshot.unsafeAsynchronousRequest(url: "https://www.apple.com",
                                  httpMethod: "GET",
                                  params: [:],
                                  headers: [:],
                                  cookies: nil,
                                  timeoutRetry: timeoutRetry,
                                  proxy: nil,
                                  body: nil) { data, response, error in
                lock.lock(); defer { lock.unlock() }
                
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
        
        wait(for: [expectation], timeout: 600)
    }
    
    func testLongshotRetryOnAnyError() {
        let expectation = XCTestExpectation(description: #function)
        
        HTTPSession.longshot.beRequest(url: "https://httpstat.us/502",
                          httpMethod: "GET",
                          params: [:],
                          headers: [:],
                          cookies: nil,
                          timeoutRetry: timeoutRetry,
                          proxy: nil,
                          body: nil,
                          Flynn.any) { data, response, error in
            XCTAssertEqual(error, "http 502")
            XCTAssertNotNil(data)
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 600)
    }
}
