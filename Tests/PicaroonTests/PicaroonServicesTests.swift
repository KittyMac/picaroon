import XCTest
import Spanker
import Hitch

@testable import Picaroon

class HelloWorldService: ServiceActor {
    private let response = HttpResponse(text: "Hello World")
            
    override func safeHandleRequest(userSession: UserServiceableSession,
                                    jsonElement: JsonElement,
                                    httpRequest: HttpRequest,
                                    _ returnCallback: @escaping (JsonElement?, HttpResponse?) -> ()) {
        returnCallback(nil, response)
    }
}

class ToUpperService: ServiceActor {
    override func safeHandleRequest(userSession: UserServiceableSession,
                                    jsonElement: JsonElement,
                                    httpRequest: HttpRequest,
                                    _ returnCallback: @escaping (JsonElement?, HttpResponse?) -> ()) {
        guard let value = jsonElement[hitch: "value"] else {
            returnCallback(JsonElement(unknown: "value field missing"), nil)
            return
        }
        value.uppercase()
        returnCallback(JsonElement(unknown: value), nil)
    }
}

class TestServicesSession: UserServiceableSession {
    public required init() {
        super.init()
        setInitialServices()
    }

    required init(cookieSessionUUID: Hitch?, javascriptSessionUUID: Hitch?) {
        super.init(cookieSessionUUID: cookieSessionUUID, javascriptSessionUUID: javascriptSessionUUID)
        setInitialServices()
    }
    
    private func setInitialServices() {
        beAdd(service: HelloWorldService())
        beAdd(service: ToUpperService())
    }
}

public class TestConnection: AnyConnection {
    public func beSetTimeout(_ timeout: TimeInterval) -> Self { return self }
    public func beSend(httpResponse: HttpResponse) -> Self { return self }
    public func beSendIfModified(httpRequest: HttpRequest,
                                 httpResponse: HttpResponse) -> Self { return self }
    public func beEndUserSession() -> Self { return self }
    public func beSendInternalError() -> Self { return self }
    public func beSendServiceUnavailable() -> Self { return self }
    public func beSendSuccess(_ message: Hitch) -> Self { return self }
    public func beSendError(_ error: Hitch) -> Self { return self }
    public func beSendNotModified() -> Self { return self }
}

final class picaroonServicesTests: XCTestCase {
    
    func testHelloWorldService0() {
        let userSession = TestServicesSession()
        let connection = TestConnection()
        
        let content: HalfHitch = """
        GET /user?state=sid%3DF3901E70-DA28-44CE-939B-D43C1CFF75CF HTTP/1.1\r
        Content-Type: text/plain\r
        Content-Length: 11\r
        \r
        Hello World
        """
        
        guard let request = HttpRequest(request: content.raw()!, size: content.count) else {
            return XCTFail()
        }
        
        userSession.beHandleRequest(connection: connection,
                                    httpRequest: request)
    }
    
    func testMultipleServiceResponseWithNoContent() {
        let expectation = XCTestExpectation(description: "success")
        
        let port = Int.random(in: 8000..<65500)
        let config = ServerConfig(address: "0.0.0.0",
                                  port: port)
        
        let server = Server<TestServicesSession>(config: config)
        let client = UserSession()
        
        server.listen()
        
        for _ in 0..<1 {
            let baseUrl = "http://127.0.0.1:\(port)/"
            let jsonRequest = #"[{"service":"ToUpperService","value":"test a"},{"service":"EchoService"},{"service":"ToUpperService","value":"test b"}]"#
            client.beUrlRequest(url: baseUrl,
                                httpMethod: "POST",
                                params: [:],
                                headers: [:],
                                body: jsonRequest.data(using: .utf8),
                                client) { data, response, error in
                XCTAssertNil(error)
                
                guard let data = data else { return XCTFail() }
                guard let dataAsString = String(data: data, encoding: .utf8) else { return XCTFail() }
                
                guard let serviceResponse: String = response?.allHeaderFields["Service-Response"] as? String else { return XCTFail() }

                XCTAssertEqual(serviceResponse, #"["TEST A","TEST B"]"#)
                XCTAssertEqual(dataAsString, "")

                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 30)
    }
    
    func testMultipleServiceResponseWithNoHeadersAndOneContent() {
        let expectation = XCTestExpectation(description: "success")
        
        let port = Int.random(in: 8000..<65500)
        let config = ServerConfig(address: "0.0.0.0",
                                  port: port)
        
        let server = Server<TestServicesSession>(config: config)
        let client = UserSession()
        
        server.listen()
        
        for _ in 0..<1 {
            let baseUrl = "http://127.0.0.1:\(port)/"
            let jsonRequest = #"{"service":"HelloWorldService"}"#
            client.beUrlRequest(url: baseUrl,
                                httpMethod: "POST",
                                params: [:],
                                headers: [:],
                                body: jsonRequest.data(using: .utf8),
                                client) { data, response, error in
                XCTAssertNil(error)
                
                guard let data = data else { return XCTFail() }
                guard let dataAsString = String(data: data, encoding: .utf8) else { return XCTFail() }
                
                guard let serviceResponse: String = response?.allHeaderFields["Service-Response"] as? String else { return XCTFail() }

                XCTAssertEqual(serviceResponse, #"null"#)
                XCTAssertEqual(dataAsString, "Hello World")

                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 30)
    }
    
    func testMultipleServiceResponseWithHeadersAndOneContent() {
        let expectation = XCTestExpectation(description: "success")
        
        let port = Int.random(in: 8000..<65500)
        let config = ServerConfig(address: "0.0.0.0",
                                  port: port)
        
        let server = Server<TestServicesSession>(config: config)
        let client = UserSession()
        
        server.listen()
        
        for _ in 0..<1 {
            let baseUrl = "http://127.0.0.1:\(port)/"
            let jsonRequest = #"[{"service":"ToUpperService","value":"test a"},{"service":"EchoService"},{"service":"ToUpperService","value":"test b"},{"service":"HelloWorldService"}]"#
            client.beUrlRequest(url: baseUrl,
                                httpMethod: "POST",
                                params: [:],
                                headers: [:],
                                body: jsonRequest.data(using: .utf8),
                                client) { data, response, error in
                XCTAssertNil(error)
                
                guard let data = data else { return XCTFail() }
                guard let dataAsString = String(data: data, encoding: .utf8) else { return XCTFail() }
                
                guard let serviceResponse: String = response?.allHeaderFields["Service-Response"] as? String else { return XCTFail() }

                XCTAssertEqual(serviceResponse, #"["TEST A","TEST B",null]"#)
                XCTAssertEqual(dataAsString, "Hello World")

                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 30)
    }
    
    func testMultipleServiceResponseWithMultipleContentError() {
        let expectation = XCTestExpectation(description: "success")
        
        let port = Int.random(in: 8000..<65500)
        let config = ServerConfig(address: "0.0.0.0",
                                  port: port)
        
        let server = Server<TestServicesSession>(config: config)
        let client = UserSession()
        
        server.listen()
        
        for _ in 0..<1 {
            let baseUrl = "http://127.0.0.1:\(port)/"
            let jsonRequest = #"[{"service":"ToUpperService","value":"test a"},{"service":"EchoService"},{"service":"HelloWorldService"},{"service":"HelloWorldService"}]"#
            client.beUrlRequest(url: baseUrl,
                                httpMethod: "POST",
                                params: [:],
                                headers: [:],
                                body: jsonRequest.data(using: .utf8),
                                client) { data, response, error in
                XCTAssertNotNil(error)
                
                guard let data = data else { return XCTFail() }
                guard let dataAsString = String(data: data, encoding: .utf8) else { return XCTFail() }
                
                guard let serviceResponse: String = response?.allHeaderFields["Service-Response"] as? String else { return XCTFail() }

                XCTAssertEqual(serviceResponse, #"["TEST A",null,null]"#)
                XCTAssertEqual(dataAsString, "HTTP/1.1 500 Internal Server Error")
                
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 30)
    }
    
    static var allTests = [
        ("testHelloWorldService0", testHelloWorldService0),
    ]
}
