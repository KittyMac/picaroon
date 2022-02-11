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

class TestServicesSession: UserServiceableSession {
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

public class TestConnection: AnyConnection {
    public func beSendData(_ data: Data) -> Self { return self }
    public func beSendDataIfChanged(_ httpRequest: HttpRequest, _ data: Data) -> Self { return self }
    public func beEndUserSession() -> Self { return self }
    public func beSendInternalError() -> Self { return self }
    public func beSendServiceUnavailable() -> Self { return self }
    public func beSendSuccess(_ message: String) -> Self { return self }
    public func beSendError(_ error: String) -> Self { return self }
    public func beSendNotModified() -> Self { return self }
    public func beSetTimeout(_ timeout: TimeInterval) -> Self { return self }
}

final class picaroonServicesTests: XCTestCase {
    
    func testHelloWorldService0() {
        let userSession = TestServicesSession()
        let connection = TestConnection()
        
        let content = """
        GET /user?state=sid%3DF3901E70-DA28-44CE-939B-D43C1CFF75CF HTTP/1.1\r
        Content-Type: text/plain\r
        Content-Length: 11\r
        \r
        Hello World
        """.halfhitch()
        
        guard let request = HttpRequest(request: content.raw()!, size: content.count) else {
            return XCTFail()
        }
        
        userSession.beHandleRequest(connection: connection,
                                    httpRequest: request)
    }
    
    func testHelloWorldService1() {
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
    
    func testHelloWorldService2() {
        let expectation = XCTestExpectation(description: "success")
        
        let port = Int.random(in: 8000..<65500)
        let config = ServerConfig(address: "0.0.0.0",
                                  port: port)
        
        let server = Server<TestServicesSession>(config: config)
        let client = UserSession()
        
        server.listen()
        
        for _ in 0..<100 {
            let baseUrl = "http://127.0.0.1:\(port)/"
            let jsonRequest = #"{"service":"HelloWorldService"}"#
            client.beUrlRequest(url: baseUrl,
                                httpMethod: "POST",
                                params: [:],
                                headers: [:],
                                body: jsonRequest.data(using: .utf8),
                                client) { data, response, error in
                //XCTAssertNil(error)
                
                guard let data = data else { return XCTFail() }
                guard let json = String(data: data, encoding: .utf8) else { return XCTFail() }

                XCTAssertEqual(json, #""Hello World!""#)
                
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 30)
    }
    
    static var allTests = [
        ("testHelloWorldService0", testHelloWorldService0),
    ]
}
