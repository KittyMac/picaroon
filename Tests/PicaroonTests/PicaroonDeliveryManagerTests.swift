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
        
        HTTPDeliveryManager.shared.beConfigure(storagePath: "/tmp",
                                               encrypt: nil,
                                               decrypt: nil)

        let group = DispatchGroup()
        
        for _ in 0..<10 {
            group.enter()
            HTTPDeliveryManager.shared.beDeliver(url: baseUrl,
                                                 httpMethod: "GET",
                                                 params: [:],
                                                 headers: [:],
                                                 proxy: nil,
                                                 body: nil,
                                                 Flynn.any) { data, response, error in
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
        
        HTTPDeliveryManager.shared.beConfigure(storagePath: "/tmp",
                                               encrypt: nil,
                                               decrypt: nil)
        
        for _ in 0..<10 {
            HTTPDeliveryManager.shared.beDeliver(url: baseUrl,
                                                 httpMethod: "GET",
                                                 params: [:],
                                                 headers: [:],
                                                 proxy: nil,
                                                 body: nil,
                                                 Flynn.any) { data, response, error in }
        }
        
        Flynn.sleep(5)

        expectation.fulfill()
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testDeliveryPersistedRequests0() {
        let expectation = XCTestExpectation(description: "success")
        
        let port = 56598
        
        HTTPDeliveryManager.shared.beConfigure(storagePath: "/tmp",
                                               encrypt: nil,
                                               decrypt: nil)
        
        Flynn.sleep(1)
        
        HTTPDeliveryManager.shared.beConfigure(storagePath: "/tmp",
                                               encrypt: nil,
                                               decrypt: nil)
        
        Flynn.sleep(1)
        
        HTTPDeliveryManager.shared.beConfigure(storagePath: "/tmp",
                                               encrypt: nil,
                                               decrypt: nil)

        let _ = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port)
        
        Flynn.sleep(5)

        expectation.fulfill()
        
        wait(for: [expectation], timeout: 30)
    }

    
}

#endif
