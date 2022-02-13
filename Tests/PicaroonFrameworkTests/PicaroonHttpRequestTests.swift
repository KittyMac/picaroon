import XCTest
@testable import PicaroonFramework

final class picaroonHttpRequestTests: XCTestCase {
    
    func testSessionIdParameter1() {
        let content = """
        GET /user?state=sid%3DF3901E70-DA28-44CE-939B-D43C1CFF75CF HTTP/1.1\r
        Content-Type: text/plain\r
        Content-Length: 11\r
        \r
        Hello World
        """.halfhitch()
        
        let request = HttpRequest(request: content.raw()!, size: content.count)!
        
        XCTAssertEqual(request.method, HttpMethod.GET)
        XCTAssertEqual(request.contentType, "text/plain")
        XCTAssertEqual(request.contentLength, "11")
        XCTAssertEqual(request.content, "Hello World")
        XCTAssertEqual(request.sid, "F3901E70-DA28-44CE-939B-D43C1CFF75CF")
        XCTAssertEqual(request.urlParameters, "state=sid%3DF3901E70-DA28-44CE-939B-D43C1CFF75CF")
        XCTAssertEqual(request.url, "/user")
    }
    
    func testSessionIdParameter2() {
        let content = """
        GET /user?sid=F3901E70-DA28-44CE-939B-D43C1CFF75CF&code=Gf0I76pKptuRrNkJfDf5QrryqQJR4B HTTP/1.1\r
        Content-Type: text/plain\r
        Content-Length: 11\r
        \r
        Hello World
        """.halfhitch()
        
        let request = HttpRequest(request: content.raw()!, size: content.count)!

        XCTAssertEqual(request.method, HttpMethod.GET)
        XCTAssertEqual(request.contentType, "text/plain")
        XCTAssertEqual(request.contentLength, "11")
        XCTAssertEqual(request.content, "Hello World")
        XCTAssertEqual(request.sid, "F3901E70-DA28-44CE-939B-D43C1CFF75CF")
        XCTAssertEqual(request.urlParameters, "sid=F3901E70-DA28-44CE-939B-D43C1CFF75CF&code=Gf0I76pKptuRrNkJfDf5QrryqQJR4B")
        XCTAssertEqual(request.url, "/user")
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
        """.halfhitch()
        
        let request = HttpRequest(request: content.raw()!, size: content.count)!

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
    
    static var allTests = [
        ("testSessionIdParameter1", testSessionIdParameter1),
        ("testSessionIdParameter2", testSessionIdParameter2),
        ("testMultipartRequest", testMultipartRequest),
    ]
}
