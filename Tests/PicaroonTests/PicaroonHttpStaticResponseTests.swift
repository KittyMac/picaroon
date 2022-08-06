import XCTest
import Hitch
import Spanker

@testable import Picaroon

class TestSocket: SocketSendable {
    static let hackDateTime: Hitch = "2022-02-12 21:05:32 +0000"
    
    private let sent = Hitch()
    
    func send(hitch: Hitch) -> Int {
        sent.append(hitch)
        return hitch.count
    }
    
    func send(data: Data) -> Int {
        sent.append(Hitch(data: data))
        return data.count
    }
    
    func send(bytes: UnsafePointer<UInt8>?, count: Int) -> Int {
        guard let bytes = bytes else { return 0 }
        sent.append(Hitch(bytes: bytes, offset: 0, count: count))
        return count
    }
    
    func result() -> Hitch {
        // we need to sanitize the result by replaceing the date/times with known quantities
        if let lastModified = sent.extract("Last-Modified: ", "\r\n") {
            sent.replace(occurencesOf: lastModified, with: TestSocket.hackDateTime)
        }
        return sent
    }
    
    func clear() {
        sent.clear()
    }
}

final class picaroonHttpStaticResponseTests: XCTestCase {
    /*
    func testPerformance1() {
        
        let port = Int.random(in: 8000..<65500)
        
        let config = ServerConfig(address: "0.0.0.0", port: port)
        
        let helloWorldResponse = HttpStaticResponse(text: "Hello World")
        
        let server = Server(config: config) { _, _ in
            return helloWorldResponse
        }
        server.listen()
        
        sleep(1)
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/wrk")
        task.arguments = [
            "-t", "4",
            "-c", "100",
            "http://localhost:\(port)/hello/world"
        ]
        
        //     /opt/homebrew/bin/wrk -t 4 -c 100 http://192.168.1.200:8080/bench
        // /opt/homebrew/bin/wrk -t 4 -c 100 http://localhost:8080/
        
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
    */
    func testProfile1() {
        // 0.006
        
        let response = HttpStaticResponse.internalServerError
        let socket = TestSocket()
        let config = ServerConfig(address: "127.0.0.1", port: 8080)
        
        measure {
            for _ in 0..<100000 {
                response.send(config: config,
                              socket: socket,
                              userSession: nil)
                
                socket.clear()
            }
        }
    }
    
    func testSimpleJson() {
        let json = JsonElement(unknown: ["1", 2, "3", 4])
        let response = HttpStaticResponse(json: json)
        let socket = TestSocket()
        let config = ServerConfig(address: "127.0.0.1", port: 8080)
        
        response.send(config: config,
                      socket: socket,
                      userSession: nil)
        
        XCTAssertEqual(socket.result(), """
        HTTP/1.1 200 OK\r
        Last-Modified: 2022-02-12 21:05:32 +0000\r
        Connection: keep-alive\r
        Content-Type: application/json\r
        Content-Length: 13\r\n\r
        ["1",2,"3",4]
        """)
    }
    
    func testSimpleText() {
        let response = HttpStaticResponse(text: "Hello World")
        let socket = TestSocket()
        let config = ServerConfig(address: "127.0.0.1", port: 8080)
        
        response.send(config: config,
                      socket: socket,
                      userSession: nil)
        
        XCTAssertEqual(socket.result(), """
        HTTP/1.1 200 OK\r
        Last-Modified: 2022-02-12 21:05:32 +0000\r
        Connection: keep-alive\r
        Content-Type: text/plain\r
        Content-Length: 11\r\n\r
        Hello World
        """)
    }
    
    func testInternalError() {
        let response = HttpStaticResponse.internalServerError
        let socket = TestSocket()
        let config = ServerConfig(address: "127.0.0.1", port: 8080)
        
        response.send(config: config,
                      socket: socket,
                      userSession: nil)
        
        XCTAssertEqual(socket.result(), """
        HTTP/1.1 500 Internal Server Error\r
        Last-Modified: 2022-02-12 21:05:32 +0000\r
        Connection: keep-alive\r
        Content-Type: txt\r
        Content-Length: 0\r\n\r\n
        """)
    }
        
    static var allTests = [
        ("testSimpleJson", testSimpleJson),
        ("testSimpleText", testSimpleText),
        ("testInternalError", testInternalError)
    ]
}
