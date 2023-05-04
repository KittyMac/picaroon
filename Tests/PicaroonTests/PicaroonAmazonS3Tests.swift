import XCTest
import Hitch
import Flynn

import Picaroon

final class PicaroonAmazonS3Tests: XCTestCase {
    let key = try! String(contentsOfFile: "/Users/rjbowli/Development/data/passwords/s3_key.txt")
    let secret = try! String(contentsOfFile: "/Users/rjbowli/Development/data/passwords/s3_secret.txt")
    
    let bucket = "sp-rover-unittest-west"
    let region = "us-west-2"
    let path = "/v1/errorlogs/test.txt"
    
    func testUploadAndDownloadS3() {
        let expectation = XCTestExpectation(description: #function)
        
        let data = Date().toISO8601Hitch().dataCopy()
        
        HTTPSession.oneshot.beUploadToS3(key: key,
                                         secret: secret,
                                         acl: nil,
                                         storageType: nil,
                                         region: region,
                                         bucket: bucket,
                                         path: path,
                                         contentType: .txt,
                                         body: data,
                                         Flynn.any) { data, response, error in
            
            XCTAssertNil(error)
            XCTAssertNotNil(data)
        }.then().doDownloadFromS3(key: key,
                                  secret: secret,
                                  region: region,
                                  bucket: bucket,
                                  path: path,
                                  contentType: .txt,
                                  Flynn.any) { data, response, error in
            guard let data = data else { XCTFail(); return }
            
            XCTAssertNil(error)
            XCTAssertNotNil(data)
            
            guard let date = Hitch(data: data).description.date() else { XCTFail(); return }
            
            XCTAssertTrue(
                abs(date.timeIntervalSinceNow) < 10.0
            )
        }.then().doListFromS3(key: key,
                              secret: secret,
                              region: region,
                              bucket: bucket,
                              path: "/v1/errorlogs/",
                              Flynn.any) { data, response, error in
            print(Hitch(data: data!))
            
            XCTAssertNil(error)
            XCTAssertNotNil(data)

            
            expectation.fulfill()

        }
        
        wait(for: [expectation], timeout: 600)
    }
         
}
