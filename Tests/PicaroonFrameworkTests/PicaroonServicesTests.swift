import XCTest
import Spanker

@testable import PicaroonFramework

class HelloWorldService: ServiceActor {
    private let response = JsonElement(unknown: "Hello World!")
            
    override func safeHandleRequest(jsonElement: JsonElement,
                                    httpRequest: HttpRequest,
                                    _ returnCallback: (JsonElement) -> ()) {
        returnCallback(response)
    }
}

class ToUpperService: ServiceActor {
    private let response = JsonElement(unknown: "Hello World!")
            
    override func safeHandleRequest(jsonElement: JsonElement,
                                    httpRequest: HttpRequest,
                                    _ returnCallback: (JsonElement) -> ()) {
        let value = jsonElement[hitch: "value"] ?? "no value"
        value.uppercase()
        returnCallback(JsonElement(unknown: value))
    }
}

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
        beAdd(service: ToUpperService())
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
        
        for _ in 0..<100 {
            let baseUrl = "http://127.0.0.1:\(port)/"
            let jsonRequest = #"[{"service":"HelloWorldService"},{"service":"EchoService"},{"service":"ToUpperService","value":"goodbye world"},{"service":"HelloWorldService"}]"#
            client.beUrlRequest(url: baseUrl,
                                httpMethod: "POST",
                                params: [:],
                                headers: [:],
                                body: jsonRequest.data(using: .utf8),
                                client) { data, response, error in
                //XCTAssertNil(error)
                
                guard let data = data else { return XCTFail() }
                guard let json = String(data: data, encoding: .utf8) else { return XCTFail() }

                XCTAssertEqual(json, #"["Hello World!","GOODBYE WORLD","Hello World!"]"#)
                
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 30)
    }
    
    static var allTests = [
        ("testHelloWorldService0", testHelloWorldService0),
    ]
}
