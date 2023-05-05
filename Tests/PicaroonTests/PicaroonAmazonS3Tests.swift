import XCTest
import Hitch
import Flynn
import Studding

import Picaroon

final class PicaroonAmazonS3Tests: XCTestCase {
    let bucket = "sp-rover-unittest-west"
    let goodPath = "/v1/errorlogs/test.txt"
    let badPath = "/test.txt"
    
    let credentials = S3Credentials(url: nil,
                                    accessKey: try! String(contentsOfFile: "/Users/rjbowli/Development/data/passwords/s3_key.txt"),
                                    secretKey: try! String(contentsOfFile: "/Users/rjbowli/Development/data/passwords/s3_secret.txt"),
                                    region: "us-west-2",
                                    service: "s3")
    
    func testUploadAndDownloadS3() {
        let expectation = XCTestExpectation(description: #function)
        
        let data = Date().toISO8601Hitch().dataCopy()
                
        HTTPSession.oneshot.beUploadToS3(credentials: credentials,
                                         acl: nil,
                                         storageType: nil,
                                         bucket: bucket,
                                         key: goodPath,
                                         contentType: .txt,
                                         body: data,
                                         Flynn.any) { data, response, error in
            
            XCTAssertNil(error)
            XCTAssertNotNil(data)
        }.then().doDownloadFromS3(credentials: credentials,
                                  bucket: bucket,
                                  key: goodPath,
                                  contentType: .txt,
                                  Flynn.any) { data, response, error in
            guard let data = data else { XCTFail(); return }
            
            XCTAssertNil(error)
            XCTAssertNotNil(data)
            
            guard let date = Hitch(data: data).description.date() else { XCTFail(); return }
            
            XCTAssertTrue(
                abs(date.timeIntervalSinceNow) < 10.0
            )
        }.then().doListFromS3(credentials: credentials,
                              bucket: bucket,
                              keyPrefix: "v1/errorlogs/",
                              marker: nil,
                              Flynn.any) { data, response, error in
            XCTAssertNil(error)
            XCTAssertNotNil(data)
            Studding.parsed(data: data!) { xml in
                guard let xml = xml else { XCTFail(); return }
                XCTAssertEqual(xml["Contents"]?["Key"]?.text, "v1/errorlogs/test.txt")
            }
        }.then().doUploadToS3(credentials: credentials,
                              acl: nil,
                              storageType: nil,
                              bucket: bucket,
                              key: badPath,
                              contentType: .txt,
                              body: data,
                              Flynn.any) { data, response, error in
            XCTAssertNotNil(error)
        }.then().doDownloadFromS3(credentials: credentials,
                                  bucket: bucket,
                                  key: badPath,
                                  contentType: .txt,
                                  Flynn.any) { data, response, error in
            XCTAssertNotNil(error)
        }.then().doListFromS3(credentials: credentials,
                              bucket: bucket,
                              keyPrefix: "/",
                              marker: nil,
                              Flynn.any) { data, response, error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 600)
    }
         
}