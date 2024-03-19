import XCTest
import Hitch
import Flynn
import Studding

import Picaroon

#if os(macOS)

final class PicaroonAmazonS3Tests: XCTestCase {
    let goodPath = "/v1/errorlogs/test.txt"
    let badPath = "/test.txt"
    
    let credentials = S3Credentials(url: nil,
                                    accessKey: try! String(contentsOfFile: "/Users/rjbowli/Development/data/passwords/s3_key.txt"),
                                    secretKey: try! String(contentsOfFile: "/Users/rjbowli/Development/data/passwords/s3_secret.txt"),
                                    baseDomain: "amazonaws.com",
                                    service: "s3",
                                    region: "us-west-2",
                                    bucket: "sp-rover-unittest-west")
    
    func testListAll() {
        let expectation = XCTestExpectation(description: #function)

        HTTPSession.oneshot.beListAllKeysFromS3(credentials: credentials,
                                                keyPrefix: "many/",
                                                marker: nil,
                                                priority: .low,
                                                Flynn.any) { objects, continuationMarker, error in
            XCTAssertNil(error)
            XCTAssertNotNil(continuationMarker)
            XCTAssertEqual(objects.count, 1349)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 600)
    }
    
    func testSyncToLocal() {
        let expectation = XCTestExpectation(description: #function)

        HTTPSession.oneshot.beSyncToLocal(credentials: credentials,
                                          keyPrefix: "v1/many/",
                                          localDirectory: "/tmp/many/",
                                          continuous: true,
                                          priority: .low,
                                          Flynn.any) { allObjects, newObjects, continuationMarker, error in
            XCTAssertNil(error)
            XCTAssertNotNil(continuationMarker)
            //XCTAssertEqual(allObjects.count, 999)
            print("TOTAL OBJECTS QUERIED FROM S3: \(allObjects.count)")
            print("DOWNLOADED: \(newObjects.count)")
            print("CONTINUATION MARKER: \(continuationMarker)")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 600)
    }
    
    func testSyncOneFileToLocal() {
        let expectation = XCTestExpectation(description: #function)
        
        HTTPSession.oneshot.beDownloadFromS3(toFilePath: "/tmp/many/file2091.txt",
                                             credentials: credentials,
                                             key: "v1/many/file2091.txt",
                                             contentType: .any,
                                             cacheTime: 30,
                                             Flynn.any) { data, source, response, error in
            XCTAssertNil(error)
            XCTAssertNotNil(data)
            
            if let source = source {
                switch source {
                case .cache:
                    print ("LOADED FROM CACHE WITHOUT REQUEST")
                case .notModified:
                    print ("LOADED FROM CACHE NOT MODIFIED")
                case .network:
                    print ("LOADED FROM NETWORK")
                }
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 600)
    }
    
    func testUploadAndDownloadS3() {
        let expectation = XCTestExpectation(description: #function)
        
        let data = Date().toISO8601Hitch().dataCopy()
                
        HTTPSession.oneshot.beUploadToS3(credentials: credentials,
                                         acl: nil,
                                         storageType: nil,
                                         key: goodPath,
                                         contentType: .txt,
                                         body: data,
                                         Flynn.any) { data, response, error in
            
            XCTAssertNil(error)
            XCTAssertNotNil(data)
        }.then().doDownloadFromS3(credentials: credentials,
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
                              keyPrefix: "v1/errorlogs/",
                              marker: nil,
                              Flynn.any) { allObjects, continuationMarker, isDone, error in
            XCTAssertNil(error)
            XCTAssertNotNil(data)
            XCTAssertEqual(allObjects.count, 2)
            
            XCTAssertEqual(allObjects[0].key, "v1/errorlogs/test.txt")
            XCTAssertEqual(allObjects[1].key, "v1/errorlogs/test2.txt")
        }.then().doUploadToS3(credentials: credentials,
                              acl: nil,
                              storageType: nil,
                              key: badPath,
                              contentType: .txt,
                              body: data,
                              Flynn.any) { data, response, error in
            XCTAssertNotNil(error)
        }.then().doDownloadFromS3(credentials: credentials,
                                  key: badPath,
                                  contentType: .txt,
                                  Flynn.any) { data, response, error in
            XCTAssertNotNil(error)
        }.then().doListFromS3(credentials: credentials,
                              keyPrefix: "/",
                              marker: nil,
                              Flynn.any) { allObjects, continuationMarker, isDone, error in
            XCTAssertNotNil(error)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 600)
    }
         
}

#endif
