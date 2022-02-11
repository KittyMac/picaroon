import XCTest
@testable import PicaroonFramework

final class picaroonBadClientTests: XCTestCase {
    
    func testBadClient0() {
        let content = "".halfhitch()
        
        XCTAssertNil(HttpRequest(request: content.raw()!, size: content.count))
    }
    
    func testBadClient1() {
        let content = "this is not a valid request".halfhitch()
        XCTAssertNil(HttpRequest(request: content.raw()!, size: content.count))
    }
    
    func testBadClient2() {
        let content = """
          GET /user?state=sid%3DF3901E70-DA28-44CE-939B-D43C1CFF75CF HTTP/1.1\r
        Content-Type: text/plain\r
        Content-Length: 11\r
        \r
        Hello World
        """.halfhitch()
        
        XCTAssertNil(HttpRequest(request: content.raw()!, size: content.count))
    }
    
    func testBadClient3() {
        let content = """
        GET /user?state=sid%3DF3901E70-DA28-44CE-939B-D43C1CFF75CF HTTP/1.1
        Content-Type: text/plain
        Content-Length: 11
        
        Hello World
        """.halfhitch()
        
        XCTAssertNil(HttpRequest(request: content.raw()!, size: content.count))
    }
    
    func testBadClient4() {
        let content = """
        GET /user?state=sid%3DF3901E70-DA28-44CE-939B-D43C1CFF75CF HTTP/1.1
        Content-Type: text/plain
        Content-Length: 1115615
        
        Hello World
        """.halfhitch()
        
        XCTAssertNil(HttpRequest(request: content.raw()!, size: content.count))
    }
    
    static var allTests = [
        ("testBadClient0", testBadClient0),
    ]
}
