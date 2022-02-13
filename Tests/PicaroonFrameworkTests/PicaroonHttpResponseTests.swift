import XCTest
import Hitch
import Spanker

@testable import PicaroonFramework

final class picaroonHttpResponseTests: XCTestCase {
        
    func testPerformance1() {
        
        let port = Int.random(in: 8000..<65500)
        
        let config = ServerConfig(address: "0.0.0.0", port: port)
        
        let helloWorldResponse = HttpResponse(text: "Hello World")
        
        let server = Server(config: config) { _ in
            return helloWorldResponse
        }
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
    
    func testProfile1() {
        // 0.697
        // 0.693
        // 0.241
        // 0.069
        
        let response = HttpResponse(status: .internalServerError, type: .txt)
        let socket = TestSocket()
        
        measure {
            for _ in 0..<100000 {
                response.send(socket: socket,
                              userSession: nil)
                
                socket.clear()
            }
        }
    }
    
    func testSimpleJson() {
        let json = JsonElement(unknown: ["1", 2, "3", 4])
        let response = HttpResponse(json: json)
        let socket = TestSocket()
        
        response.send(socket: socket,
                      userSession: nil)
        
        XCTAssertEqual(socket.result(), """
        HTTP/1.1 200 OK\r
        Last-Modified:2022-02-12 21:05:32 +0000\r
        Connection:keep-alive\r
        Content-Type:application/json\r
        Content-Length:13\r\n\r
        ["1",2,"3",4]
        """)
    }
    
    func testSimpleText() {
        let response = HttpResponse(text: "Hello World")
        let socket = TestSocket()
        
        response.send(socket: socket,
                      userSession: nil)
        
        XCTAssertEqual(socket.result(), """
        HTTP/1.1 200 OK\r
        Last-Modified:2022-02-12 21:05:32 +0000\r
        Connection:keep-alive\r
        Content-Type:text/plain\r
        Content-Length:11\r\n\r
        Hello World
        """)
    }
        
    func testSimpleMultipart() {
        let response = HttpResponse(multipart: [
            HttpResponse(text: "Part 1", multipartName: "ServiceActor.0"),
            HttpResponse(text: "Part 2", multipartName: "ServiceActor.1")
        ])
        let socket = TestSocket()
        
        response.send(socket: socket,
                      userSession: nil)
        
        XCTAssertEqual(socket.result(), """
        HTTP/1.1 200 OK\r
        Last-Modified:2022-02-12 21:05:32 +0000\r
        Connection:keep-alive\r
        Content-Type:multipart/form-data\r
        Content-Length:288\r
        \r
        ------WebKitFormBoundaryd9xBKq96rap8J36e\r
        Content-Disposition:form-data;name="ServiceActor.0"\r
        Content-Length:6\r
        \r
        Part 1\r
        ------WebKitFormBoundaryd9xBKq96rap8J36e\r
        Content-Disposition:form-data;name="ServiceActor.1"\r
        Content-Length:6\r
        \r
        Part 2\r
        ------WebKitFormBoundaryd9xBKq96rap8J36e\r\n
        """)
    }
    
    static var allTests = [
        ("testSimpleJson", testSimpleJson),
        ("testSimpleText", testSimpleText),
        ("testSimpleMultipart", testSimpleMultipart),
    ]
}
