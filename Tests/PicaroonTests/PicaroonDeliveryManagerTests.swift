import XCTest
import Hitch
import Flynn
import Studding

import Picaroon

#if os(macOS)

final class PicaroonDeliveryManagerTests: XCTestCase {
    
    func testSimpleDelivery0() {
        let expectation = XCTestExpectation(description: "success")
        
        let port = Int.random(in: 8000..<65500)
        let baseUrl = "http://127.0.0.1:\(port)/"

        
        let deliveryManager = HTTPDeliveryManager(storagePath: "/tmp",
                                                  encrypt: nil,
                                                  decrypt: nil)
        
        let group = DispatchGroup()
        
        for _ in 0..<10 {
            group.enter()
            deliveryManager.beDeliver(url: baseUrl,
                                      httpMethod: "GET",
                                      params: [:],
                                      headers: [:],
                                      body: nil,
                                      proxy: nil,
                                      priority: .medium,
                                      maxAttempts: 0) { data, response, error in
                XCTAssertNil(error)
                XCTAssertNotNil(data)
                group.leave()
            }
        }
        
        
        print("waiting for server to start")
        Flynn.sleep(5)

        let _ = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port)
        
        group.notify(actor: Flynn.any) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 30)
    }
    
    func testDeliveryCreateRequests0() {
        let expectation = XCTestExpectation(description: "success")

        let port = 56598
        let baseUrl = "http://127.0.0.1:\(port)/"

        let deliveryManager = HTTPDeliveryManager(storagePath: "/tmp",
                                                  encrypt: nil,
                                                  decrypt: nil)
        for _ in 0..<10 {
            deliveryManager.beDeliver(url: baseUrl,
                                      httpMethod: "GET",
                                      params: [:],
                                      headers: [:],
                                      body: nil,
                                      proxy: nil,
                                      priority: .medium,
                                      maxAttempts: 0) { data, response, error in }
        }
        
        Flynn.sleep(5)

        expectation.fulfill()
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testDeliveryPersistedRequests0() {
        let expectation = XCTestExpectation(description: "success")
        
        let port = 56598
        
        let _ = HTTPDeliveryManager(storagePath: "/tmp",
                                    encrypt: nil,
                                    decrypt: nil)
        
        let _ = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port)
        
        Flynn.sleep(5)

        expectation.fulfill()
        
        wait(for: [expectation], timeout: 30)
    }

    
}

#endif
