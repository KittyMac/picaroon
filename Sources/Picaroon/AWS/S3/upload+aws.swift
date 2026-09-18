// flynn:ignore Weak Timer Violation

import Foundation
import Flynn
import Hitch
import CryptoSwift

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// aws s3 cp myfile.txt s3://your-bucket-name/renamed-file.txt

extension HTTPSession {
    
    internal func _beUploadToS3(credentials: S3Credentials,
                                key: String,
                                filePath: String,
                                _ returnCallback: @escaping (String?) -> Void) {
#if os(macOS) || os(Linux)
        guard let path = pathFor(executable: "aws") else {
            return returnCallback("failed to find aws cli")
        }
        
        S3CommandRunner.next().beUpload(executable: path,
                                        credentials: credentials,
                                        key: key,
                                        filePath: filePath,
                                        self) { error in
            returnCallback(error)
        }
#else
        returnCallback("unsupported platform")
#endif
    }
    
}
