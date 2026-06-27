import Foundation
import Flynn
import Hitch
import CryptoSwift

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

fileprivate func pathFor(executable name: String) -> String? {
    let paths = [
        name,
        "/opt/awscli/bin/\(name)",
        "/Users/rjbowli/.local/bin/\(name)",
        "/opt/homebrew/bin/\(name)",
        "/usr/bin/\(name)",
        "/usr/local/bin/\(name)",
        "/bin/\(name)",
        "./\(name)"
    ]
    for path in paths where FileManager.default.fileExists(atPath:path) {
        return path
    }
    return nil
}

extension HTTPSession {
    
    private func confirmConfigFile(maxConcurrent: Int) -> String {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("aws-config")
        let contents = """
        [default]
        s3 =
          max_concurrent_requests = \(maxConcurrent)
        """
        try? contents.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }
    
    public func beSyncToLocalAWS(credentials: S3Credentials,
                                 keyPrefix: String,
                                 localDirectory: String,
                                 continuous: Bool,
                                 priority: HTTPSessionPriority,
                                 progressCallback: @escaping (Int, Int, Int) -> (),
                                 _ sender: Actor,
                                 _ returnCallback: @escaping ([S3Object], [S3Object], String?, String?) -> Void) {
        unsafeSend { _ in
#if os(macOS) || os(Linux)
            guard let path = pathFor(executable: "aws") else {
                return returnCallback([], [], nil, "failed to find aws cli")
            }
            
            Thread {
                Flynn.threadSetName("AWS.S3")
                
                
                var arguments: [String] = [
                    "s3",
                    "sync",
                    "s3://\(credentials.bucket)/\(keyPrefix)",
                    localDirectory,
                    "--no-progress"
                ]
                
                if continuous {
                    let localDirectoryUrl = URL(fileURLWithPath: localDirectory)
                    var localFilesByS3Key: [String: LocalFile] = [:]
                    var localFilesSorted: [LocalFile] = []
                    if let enumerator = FileManager.default.enumerator(at: localDirectoryUrl,
                                                                       includingPropertiesForKeys: [.isRegularFileKey],
                                                                       options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                        for case let fileURL as URL in enumerator {
                            guard let resourceValues = try? fileURL.resourceValues(forKeys: Set([.isRegularFileKey])) else { continue }
                            guard resourceValues.isRegularFile == true else { continue }
                            
                            // Note: this does not handle paths which repeat like /a/b/and/more/a/b/and/file.txt?
                            guard let relativePath = fileURL.path.components(separatedBy: localDirectoryUrl.path).last else { continue }
                            var s3Key = keyPrefix + relativePath
                            s3Key = s3Key.replacingOccurrences(of: "//", with: "/")
                            
                            let localFile = LocalFile(name: fileURL.lastPathComponent,
                                                      path: fileURL.path,
                                                      s3Key: s3Key)
                            
                            localFilesByS3Key[s3Key] = localFile
                            localFilesSorted.append(localFile)
                        }
                    }
                    
                    localFilesSorted.sort()
                    
                    // If our sorting of the local files and s3 bucket were perfect, then we could pick up
                    // where the last file left off. However, given time drift of user devices it is entirely
                    // possible that the sorting will leave gaps. To combat this, we allow up to one extra list
                    // API call for continuous pulls.
                    if localFilesSorted.count >= 999 {
                        let marker = localFilesSorted[localFilesSorted.count - 999].s3Key
                        arguments.append("--start-after")
                        arguments.append(marker)
                    }
                }
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                
                
                var env = ProcessInfo.processInfo.environment
                env["AWS_CONFIG_FILE"] = self.confirmConfigFile(maxConcurrent: 64)
                env["AWS_ACCESS_KEY_ID"] = credentials.accessKey
                env["AWS_SECRET_ACCESS_KEY"] = credentials.secretKey
                env["AWS_DEFAULT_REGION"] = credentials.region
                process.environment = env
                
                let outputPipe = Pipe()
                process.standardOutput = outputPipe
                
                try? process.run()
                
                var allObjects: [S3Object] = []
                var error: String? = nil
                
                outputPipe.fileHandleForWriting.closeFile()
                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    if let lines = String(data: handle.availableData, encoding: .utf8), !lines.isEmpty {
                        for line in lines.components(separatedBy: "\n") {
                            let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard line.isEmpty == false else { continue }
                            
                            if let object = S3Object.from(awsLog: line) {
                                allObjects.append(object)
                            } else {
                                error = "failed to parse aws output: \(line)"
                            }
                        }
                        
                        sender.unsafeSend { _ in
                            progressCallback(0, allObjects.count, allObjects.count)
                        }
                    }
                }
                
                process.waitUntilExit()
                
                guard process.terminationStatus == 0 else {
                    return returnCallback([], [], nil, "aws cli failed code \(process.terminationStatus)")
                }
                
                return returnCallback(allObjects, allObjects, nil, error)
            }.start()
#else
            self.beSyncToLocal(credentials: credentials,
                               keyPrefix: keyPrefix,
                               localDirectory: localDirectory,
                               continuous: continuous,
                               priority: priority,
                               progressCallback: progressCallback,
                               sender,
                               returnCallback)
#endif
        }
    }
    
}
