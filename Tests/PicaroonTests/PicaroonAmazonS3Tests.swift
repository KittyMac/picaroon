import XCTest
import Hitch
import Flynn

import Picaroon

final class PicaroonAmazonS3Tests: XCTestCase {
    let key = try! String(contentsOfFile: "/Users/rjbowli/Development/data/passwords/s3_0.txt")
    let secret = try! String(contentsOfFile: "/Users/rjbowli/Development/data/passwords/s3_1.txt")
    
    func testUploadToS3() {
        let expectation = XCTestExpectation(description: #function)
        
        let data = Date().toISO8601Hitch().dataCopy()
        
        HTTPSession.oneshot.beUploadToS3(key: key,
                                         secret: secret,
                                         bucket: "sp-rover-staging",
                                         path: "v1/errorlogs/test.txt",
                                         contentType: .txt,
                                         body: data,
                                         Flynn.any) { data, response, error in
            
            XCTAssertNil(error)
            XCTAssertNotNil(data)
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 600)
    }
         
}
