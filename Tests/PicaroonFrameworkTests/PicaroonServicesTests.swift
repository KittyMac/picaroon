import XCTest
@testable import PicaroonFramework

class TestServicesSession: UserServicableSession {
    public required init() {
        super.init()
        setInitialServices()
    }

    required init(cookieSessionUUID: String?, javascriptSessionUUID: String?) {
        super.init(cookieSessionUUID: cookieSessionUUID, javascriptSessionUUID: javascriptSessionUUID)
        setInitialServices()
    }
    
    private func setInitialServices() {
        beAdd(service: HelloWorldService())
    }
}

final class picaroonServicesTests: XCTestCase {
    
    func testHelloWorldService0() {
        let expectation = XCTestExpectation(description: "success")
        
        let port = Int.random(in: 8000..<65500)
        let config = ServerConfig(address: "0.0.0.0",
                                  port: port)
        
        let server = Server<TestServicesSession>(config: config)
        let client = UserSession()
        
        server.listen()
        
        let baseUrl = "http://127.0.0.1:\(port)/"
        let jsonRequest = #"[{"service":"HelloWorldService"}]"#
        client.beUrlRequest(url: baseUrl,
                            httpMethod: "POST",
                            params: [:],
                            headers: [:],
                            body: jsonRequest.data(using: .utf8),
                            client) { data, response, error in
            XCTAssertNil(error)
            
            guard let data = data else { return XCTFail() }
            guard let json = String(data: data, encoding: .utf8) else { return XCTFail() }

            XCTAssertEqual(json, #"["Hello World!"]"#)
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    static var allTests = [
        ("testHelloWorldService0", testHelloWorldService0),
    ]
}
