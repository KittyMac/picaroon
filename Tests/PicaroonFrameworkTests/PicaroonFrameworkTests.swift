import XCTest
@testable import PicaroonFramework

final class picaroonTests: XCTestCase {
    
    let helloWorldResponse = HttpResponse.asData(nil, .ok, .txt, "Hello World")

    class HelloWorld: UserSession {
        override func safeHandleRequest(_ connection: AnyConnection, _ httpRequest: HttpRequest) {
            connection.beSendInternalError()
        }
    }

    func handleStaticRequest(_ httpRequest: HttpRequest) -> Data? {
        return helloWorldResponse
    }
    
    func testSessionIdParameter1() {
        let content = """
        GET /user?state=sid%3DF3901E70-DA28-44CE-939B-D43C1CFF75CF&code=Gf0I76pKptuRrNkJfDf5QrryqQJR4B HTTP/1.1\r
        Content-Type: text/plain\r
        Content-Length: 11\r
        \r
        Hello World
        """.data(using: .utf8)!
        
        content.withUnsafeBytes { (buffer: UnsafePointer<CChar>) -> () in
            let request = HttpRequest(request: buffer, size: content.count)
            
            XCTAssertEqual(request.method, HttpMethod.GET)
            XCTAssertEqual(request.contentType, "text/plain")
            XCTAssertEqual(request.contentLength, "11")
            XCTAssertEqual(request.content!.count, 11)
            XCTAssertEqual(request.sessionId, "F3901E70-DA28-44CE-939B-D43C1CFF75CF")
            XCTAssertEqual(request.urlParameters, "state=sid%3DF3901E70-DA28-44CE-939B-D43C1CFF75CF&code=Gf0I76pKptuRrNkJfDf5QrryqQJR4B")
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
        
        content.withUnsafeBytes { (buffer: UnsafePointer<CChar>) -> () in
            let request = HttpRequest(request: buffer, size: content.count)
            
            XCTAssertEqual(request.method, HttpMethod.GET)
            XCTAssertEqual(request.contentType, "text/plain")
            XCTAssertEqual(request.contentLength, "11")
            XCTAssertEqual(request.content!.count, 11)
            XCTAssertEqual(request.sessionId, "F3901E70-DA28-44CE-939B-D43C1CFF75CF")
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
        
        content.withUnsafeBytes { (buffer: UnsafePointer<CChar>) -> () in
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
                                        staticStorageHandler: handleStaticRequest)
        server.listen()
        
        sleep(1)
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/local/bin/wrk")
        task.arguments = [
            "-t", "4",
            "-c", "100",
            "http://localhost:\(port)/hello/world"
        ]
        
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

    static var allTests = [
        ("testPerformance1", testPerformance1),
    ]
}
