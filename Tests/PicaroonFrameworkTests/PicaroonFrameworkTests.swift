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

    
    func testPerformance1() {
        
        let server = Server<HelloWorld>("0.0.0.0", 8080, handleStaticRequest)
        server.listen()
        
        sleep(1)
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/local/bin/wrk")
        task.arguments = [
            "-t", "4",
            "-c", "100",
            "http://localhost:8080/hello/world"
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
