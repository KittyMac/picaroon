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

        try! task.run()
        
        task.waitUntilExit()
        
        server.stop()
    }

    static var allTests = [
        ("testPerformance1", testPerformance1),
    ]
}
