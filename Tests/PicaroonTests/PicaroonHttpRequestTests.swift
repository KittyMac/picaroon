import XCTest
import Hitch

import Picaroon

final class picaroonHttpRequestTests: XCTestCase {
    
    let serverConfig = ServerConfig(address: "127.0.0.1", port: 8080)
    
    func testCookies() {
        let content: HalfHitch = """
        POST /? HTTP/1.1\r
        Host: 127.0.0.1:49509\r
        Accept: */*\r
        Authorization: Bearer HelloWorld\r
        Cache-Control: no-cache\r
        User-Agent: xctest/18143 CFNetwork/1237 Darwin/20.4.0\r
        Connection: keep-alive\r
        Cookie: FABE1A47-B2FD-4CC3-AB92-D1F570002158=6AF73CB5-4D6A-4CBD-A893-89074F1F51CF\r
        Session-Id: 6AF73CB5-4D6A-4CBD-A893-89074F1F51CF\r
        Device-Id: 0123456789\r
        Accept-Language: en-us\r
        Accept-Encoding: gzip, deflate\r\n\r\n
        """
        
        let request = HttpRequest(config: serverConfig,
                                  request: content.raw()!,
                                  size: content.count)!
        
        XCTAssertEqual(request.method, HttpMethod.POST)
        XCTAssertEqual(request.url, "/")
        XCTAssertEqual(request.userAgent, "xctest/18143 CFNetwork/1237 Darwin/20.4.0")
        XCTAssertEqual(request.authorization, "Bearer HelloWorld")
        XCTAssertEqual(request.connection, "keep-alive")
        XCTAssertEqual(request.cookie, "FABE1A47-B2FD-4CC3-AB92-D1F570002158=6AF73CB5-4D6A-4CBD-A893-89074F1F51CF")
        XCTAssertEqual(request.cookies["FABE1A47-B2FD-4CC3-AB92-D1F570002158"], "6AF73CB5-4D6A-4CBD-A893-89074F1F51CF")
        XCTAssertEqual(request.sid, nil)
        XCTAssertEqual(request.sessionId, "6AF73CB5-4D6A-4CBD-A893-89074F1F51CF")
        XCTAssertEqual(request.deviceId, "0123456789")
        XCTAssertEqual(request.acceptLanguage, "en-us")
        XCTAssertEqual(request.acceptEncoding, "gzip, deflate")
    }
    
    func testSessionIdParameter1() {
        let content: HalfHitch = """
        GET /user?state=sid%3DF3901E70-DA28-44CE-939B-D43C1CFF75CF HTTP/1.1\r
        Content-Type: text/plain\r
        Content-Length: 11\r
        \r
        Hello World
        """
        
        let request = HttpRequest(config: serverConfig,
                                  request: content.raw()!,
                                  size: content.count)!
        
        XCTAssertEqual(request.method, HttpMethod.GET)
        XCTAssertEqual(request.contentType, "text/plain")
        XCTAssertEqual(request.contentLength, "11")
        XCTAssertEqual(request.content, "Hello World")
        XCTAssertEqual(request.sid, "F3901E70-DA28-44CE-939B-D43C1CFF75CF")
        XCTAssertEqual(request.urlParameters, "state=sid%3DF3901E70-DA28-44CE-939B-D43C1CFF75CF")
        XCTAssertEqual(request.url, "/user")
    }
    
    func testSessionIdParameter2() {
        let content: HalfHitch = """
        GET /user?sid=F3901E70-DA28-44CE-939B-D43C1CFF75CF&code=Gf0I76pKptuRrNkJfDf5QrryqQJR4B HTTP/1.1\r
        Content-Type: text/plain\r
        Content-Length: 11\r
        \r
        Hello World
        """
        
        let request = HttpRequest(config: serverConfig,
                                  request: content.raw()!,
                                  size: content.count)!

        XCTAssertEqual(request.method, HttpMethod.GET)
        XCTAssertEqual(request.contentType, "text/plain")
        XCTAssertEqual(request.contentLength, "11")
        XCTAssertEqual(request.content, "Hello World")
        XCTAssertEqual(request.sid, "F3901E70-DA28-44CE-939B-D43C1CFF75CF")
        XCTAssertEqual(request.urlParameters, "sid=F3901E70-DA28-44CE-939B-D43C1CFF75CF&code=Gf0I76pKptuRrNkJfDf5QrryqQJR4B")
        XCTAssertEqual(request.url, "/user")
    }

    func testMultipartRequest() {
        let content: HalfHitch = """
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
        """
        
        let request = HttpRequest(config: serverConfig,
                                  request: content.raw()!,
                                  size: content.count)!

        XCTAssertEqual(request.method, HttpMethod.GET)
        XCTAssertEqual(request.contentType, "multipart/form-data")
        XCTAssertEqual(request.contentLength, "303")
        
        let parts = request.multipartContent
        
        XCTAssertEqual(parts.count, 2)
        
        XCTAssertEqual(parts[0].contentDisposition, #"form-data; name="type""#)
        XCTAssertEqual(parts[0].content, "UploadClassificationsFile")
        
        XCTAssertEqual(parts[1].contentDisposition, #"form-data; name="file"; filename="test1.txt""#)
        XCTAssertEqual(parts[1].contentType, #"text/plain"#)
        XCTAssertEqual(parts[1].content, "test 1\n")
    }
}
