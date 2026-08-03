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
        
        Thread {
            Flynn.threadSetName("AWS.S3")
            
            // https://sp-rover-unittest-west.s3.us-west-2.amazonaws.com/v1/errorlogs/test.txt
            let keyPath = (key.hasPrefix("/") ? key : "/" + key).replacingOccurrences(of: " ", with: "+")
            
            let arguments: [String] = [
                "s3",
                "cp",
                filePath,
                "s3://\(credentials.bucket)\(keyPath)",
                "--no-progress"
            ]
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            
            var env = ProcessInfo.processInfo.environment
            env["AWS_ACCESS_KEY_ID"] = credentials.accessKey
            env["AWS_SECRET_ACCESS_KEY"] = credentials.secretKey
            env["AWS_DEFAULT_REGION"] = credentials.region
            process.environment = env
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            
            try? process.run()
            
            process.waitUntilExit()
            
            guard process.terminationStatus == 0 else {
                return returnCallback("aws cli failed code \(process.terminationStatus)")
            }
            
            return returnCallback(nil)
        }.start()
#else
        returnCallback("unsupported platform")
#endif
    }
    
}
