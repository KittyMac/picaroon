import XCTest
import Hitch

import Picaroon

final class picaroonBadClientTests: XCTestCase {
    
    let serverConfig = ServerConfig(address: "127.0.0.1", port: 8080)
    
    func testBadClient0() {
        let content: HalfHitch = ""
        
        XCTAssertNil(HttpRequest(config: serverConfig,
                                 request: content.raw()!,
                                 size: content.count))
    }
    
    func testBadClient1() {
        let content: HalfHitch = "this is not a valid request"
        XCTAssertNil(HttpRequest(config: serverConfig,
                                 request: content.raw()!,
                                 size: content.count))
    }
    
    func testBadClient2() {
        let content: HalfHitch = """
          GET /user?state=sid%3DF3901E70-DA28-44CE-939B-D43C1CFF75CF HTTP/1.1\r
        Content-Type: text/plain\r
        Content-Length: 11\r
        \r
        Hello World
        """
        
        XCTAssertNil(HttpRequest(config: serverConfig,
                                 request: content.raw()!,
                                 size: content.count))
    }
    
    func testBadClient3() {
        let content: HalfHitch = """
        GET /user?state=sid%3DF3901E70-DA28-44CE-939B-D43C1CFF75CF HTTP/1.1
        Content-Type: text/plain
        Content-Length: 11
        
        Hello World
        """
        
        XCTAssertNil(HttpRequest(config: serverConfig,
                                 request: content.raw()!,
                                 size: content.count))
    }
    
    func testBadClient4() {
        let content: HalfHitch = """
        GET /user?state=sid%3DF3901E70-DA28-44CE-939B-D43C1CFF75CF HTTP/1.1
        Content-Type: text/plain
        Content-Length: 1115615
        
        Hello World
        """
        
        XCTAssertNil(HttpRequest(config: serverConfig, request: content.raw()!, size: content.count))
    }
}
