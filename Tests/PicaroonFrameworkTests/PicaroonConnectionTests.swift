import XCTest
@testable import PicaroonFramework

let helloWorldResponse = HttpResponse.asData(nil, .ok, .txt, "Hello World")

class HelloWorld: UserSession {
    override func safeHandleRequest(connection: AnyConnection,
                                    httpRequest: HttpRequest) {
        connection.beSendInternalError()
    }
}

func handleHelloWorldStaticRequest(_ httpRequest: HttpRequest) -> Data? {
    return helloWorldResponse
}



final class picaroonConnectionTests: XCTestCase {
    
    func testSessionIdParameter1() {
        let content = """
        GET /user?state=sid%3DF3901E70-DA28-44CE-939B-D43C1CFF75CF HTTP/1.1\r
        Content-Type: text/plain\r
        Content-Length: 11\r
        \r
        Hello World
        """.data(using: .utf8)!
        
        content.withUnsafeBytes { buffer in
            let request = HttpRequest(request: buffer, size: content.count)
            
            XCTAssertEqual(request.method, HttpMethod.GET)
            XCTAssertEqual(request.contentType, "text/plain")
            XCTAssertEqual(request.contentLength, "11")
            XCTAssertEqual(request.content!.count, 11)
            XCTAssertEqual(request.sid, "F3901E70-DA28-44CE-939B-D43C1CFF75CF")
            XCTAssertEqual(request.urlParameters, "state=sid%3DF3901E70-DA28-44CE-939B-D43C1CFF75CF")
            XCTAssertEqual(request.url, "/user")
        }
    }
    
    func testSessionIdParameter2() {
        let content = """
        GET /user?sid=F3901E70-DA28-44CE-939B-D43C1CFF75CF&code=Gf0I76pKptuRrNkJfDf5QrryqQJR4B HTTP/1.1\r
        Content-Type: text/plain\r
        Content-Length: 11\r
        \r
        Hello World
        """.data(using: .utf8)!
        
        content.withUnsafeBytes { buffer in
            let request = HttpRequest(request: buffer, size: content.count)
            
            XCTAssertEqual(request.method, HttpMethod.GET)
            XCTAssertEqual(request.contentType, "text/plain")
            XCTAssertEqual(request.contentLength, "11")
            XCTAssertEqual(request.content!.count, 11)
            XCTAssertEqual(request.sid, "F3901E70-DA28-44CE-939B-D43C1CFF75CF")
            XCTAssertEqual(request.urlParameters, "sid=F3901E70-DA28-44CE-939B-D43C1CFF75CF&code=Gf0I76pKptuRrNkJfDf5QrryqQJR4B")
            XCTAssertEqual(request.url, "/user")
        }
    }

    func testMultipartRequest() {
        let content = """
        GET / HTTP/1.1\r
        Content-Type: multipart/form-data\r
        Content-Length: 303\r
        \r
        ------WebKitFormBoundaryd9xBKq96rap8J36e\r
        Content-Disposition: form-data; name="type"\r
        \r
        UploadClassificationsFile\r
        ------WebKitFormBoundaryd9xBKq96rap8J36e\r
        Content-Disposition: form-data; name="file"; filename="test1.txt"\r
        Content-Type: text/plain\r
        \r
        test 1
        \r
        ------WebKitFormBoundaryd9xBKq96rap8J36e--\r
        """.data(using: .utf8)!
        
        content.withUnsafeBytes { buffer in
            let request = HttpRequest(request: buffer, size: content.count)
            
            XCTAssertEqual(request.method, HttpMethod.GET)
            XCTAssertEqual(request.contentType, "multipart/form-data")
            XCTAssertEqual(request.contentLength, "303")
            
            let parts = request.multipartContent
            
            XCTAssertEqual(parts.count, 2)
            
            XCTAssertEqual(parts[0].contentDisposition, #"form-data; name="type""#)
            XCTAssertEqual(String(data: parts[0].content!, encoding: .utf8), "UploadClassificationsFile")
            
            XCTAssertEqual(parts[1].contentDisposition, #"form-data; name="file"; filename="test1.txt""#)
            XCTAssertEqual(parts[1].contentType, #"text/plain"#)
            XCTAssertEqual(String(data: parts[1].content!, encoding: .utf8), "test 1\n")
        }
    }
        
    func testPerformance1() {
        
        let port = Int.random(in: 8000..<65500)
        
        let config = ServerConfig(address: "0.0.0.0", port: port)
        
        let server = Server<HelloWorld>(config: config,
                                        staticStorageHandler: handleHelloWorldStaticRequest)
        server.listen()
        
        sleep(1)
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/local/bin/wrk")
        task.arguments = [
            "-t", "4",
            "-c", "100",
            "http://localhost:\(port)/hello/world"
        ]
        
        //     /usr/local/bin/wrk -t 4 -c 100 http://192.168.1.200:8080/bench
        // /usr/local/bin/wrk -t 4 -c 100 http://localhost:8080/
        
        let outputPipe = Pipe()
        task.standardOutput = outputPipe

        try! task.run()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outputData, as: UTF8.self)
        
        var requestsPerSecond: Float = 0.0
        output.matches(#"Requests\/sec:\s*([\d]+\.[\d]+)"#) { (_, groups) in
            if groups.count >= 2 {
                if let f = Float(groups[1]) {
                    requestsPerSecond = f
                }
            }
        }
        
        task.waitUntilExit()
        server.stop()
        
        print(output)
        
        XCTAssertTrue(requestsPerSecond > 90000)
    }
    
    func testSimpleConnectionPersistance() {
        let expectation = XCTestExpectation(description: "success")
        
        let port = Int.random(in: 8000..<65500)
        
        let webserver = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port)
        
        let webview = PicaroonTesting.WebView()
        let baseUrl = "http://127.0.0.1:\(port)/"
        
        // Initial page load will generate a UserSession on thes server and send us back a cookie sessionUUID
        webview.load(url: baseUrl) { data, response, error in
            webview.ajax(payload: #"{"className":"Server_GetPedia","language":"en"}"#, nil)
            webview.ajax(payload: #"{"className":"Server_GetSettings"}"#) { data, response, error in
                XCTAssertEqual(webserver.numberOfUserSessions(), 1)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testMultipleConnectionPersistance() {
        let expectation = XCTestExpectation(description: "success")
        
        let port = Int.random(in: 8000..<65500)
        
        let webserver = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port)
        
        let testConnection: () -> () = {
            let webview = PicaroonTesting.WebView()
            let baseUrl = "http://127.0.0.1:\(port)/"
            
            // Initial page load will generate a UserSession on thes server and send us back a cookie sessionUUID
            webview.load(url: baseUrl) { data, response, error in
                webview.ajax(payload: #"{"className":"Server_GetPedia","language":"en"}"#, nil)
                webview.ajax(payload: #"{"className":"Server_GetSettings"}"#) { data, response, error in
                    XCTAssertEqual(webserver.numberOfUserSessions(), 3)
                    expectation.fulfill()
                }
            }
        }
        
        testConnection()
        testConnection()
        testConnection()
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testConnectionReassociation() {
        let expectation = XCTestExpectation(description: "success")
        
        let port = Int.random(in: 8000..<65500)
        
        let webserver = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port)
        
        let webview1 = PicaroonTesting.WebView()
        let baseUrl = "http://127.0.0.1:\(port)/"
        
        // Initial page load will generate a UserSession on thes server and send us back a cookie sessionUUID
        webview1.load(url: baseUrl) { data, response, error in
            XCTAssertNotNil(data)
            XCTAssertNil(error)
                            
            webview1.ajax(payload: #"{"className":"Server_AllowReassociation"}"#) { data, response, error in
                XCTAssertNotNil(data)
                XCTAssertNil(error)
                
                let firstActorSessionUUID = webview1.serverActorSessionUUID
                webview1.clearCookies()
                
                webview1.ajax(payload: #"{"className":"Server_GetSettings"}"#) { data, response, error in
                    XCTAssertNotNil(data)
                    XCTAssertNil(error)
                    
                    XCTAssertEqual(webserver.numberOfUserSessions(), 1)
                    XCTAssertEqual(firstActorSessionUUID, webview1.serverActorSessionUUID)

                    expectation.fulfill()
                }
            }
        }
        
        wait(for: [expectation], timeout: 30)
    }
    
    func testConnectionReassociationBySidInUrl() {
        let expectation = XCTestExpectation(description: "success")
        
        let port = Int.random(in: 8000..<65500)
        
        let webserver = PicaroonTesting.WebServer<PicaroonTesting.WebUserSession>(port: port)
        
        let webview1 = PicaroonTesting.WebView()
        let baseUrl = "http://127.0.0.1:\(port)/"
        
        // Initial page load will generate a UserSession on thes server and send us back a cookie sessionUUID
        webview1.load(url: baseUrl) { data, response, error in
            XCTAssertNotNil(data)
            XCTAssertNil(error)
                        
            webview1.ajax(payload: #"{"className":"Server_AllowReassociation"}"#) { data, response, error in
                XCTAssertNotNil(data)
                XCTAssertNil(error)
                
                let webview2 = PicaroonTesting.WebView()
                let sid = webview1.javascriptSessionUUID ?? "unknown"
                webview2.load(url: baseUrl + "?sid=\(sid)") { data, response, error in
                    print("1: " + (webview2.javascriptSessionUUID ?? "unknown"))
                    XCTAssertNotNil(data)
                    XCTAssertNil(error)
                                        
                    webview2.ajax(payload: #"{"className":"Server_GetSettings"}"#) { data, response, error in
                        print("3: " + (webview2.javascriptSessionUUID ?? "unknown"))
                        XCTAssertNotNil(data)
                        XCTAssertNil(error)
                        
                        XCTAssertEqual(webserver.numberOfUserSessions(), 1)
                        XCTAssertEqual(webview1.serverActorSessionUUID, webview2.serverActorSessionUUID)
                        
                        expectation.fulfill()
                    }
                }
            }
        }
        
        wait(for: [expectation], timeout: 2)
    }

    static var allTests = [
        ("testPerformance1", testPerformance1),
    ]
}
