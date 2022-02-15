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
        // 0.062
        
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
    
    func testProfileGzippedResource2() {
        // 0.794
        // 0.286
        // 0.278
        
        let socket = TestSocket()
        
        measure {
            for _ in 0..<100000 {
                let response = HttpResponse(javascript: compressedScriptCombinedJs,
                                            encoding: HttpEncoding.gzip.rawValue)
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
    
    static var allTests = [
        ("testSimpleJson", testSimpleJson),
        ("testSimpleText", testSimpleText)
    ]
}


private let compressedScriptCombinedJs = Data(base64Encoded:"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")!
