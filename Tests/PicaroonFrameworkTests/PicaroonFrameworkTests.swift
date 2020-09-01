import XCTest
@testable import PicaroonFramework

final class picaroonTests: XCTestCase {
    
    class HelloWorld: Picaroon.UserSession {
        override func safeHandleRequest(_ connection: AnyConnection, _ httpRequest: Picaroon.HttpRequest) {
            connection.beSendData(Picaroon.HttpResponse.asData(self, .ok, .txt, "Hello World"))
        }
    }
    
    func testPerformance1() {
        
        let server = Picaroon.Server<HelloWorld>("0.0.0.0", 8080)
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
