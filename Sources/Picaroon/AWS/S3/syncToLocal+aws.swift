import Foundation
import Flynn
import Hitch
import CryptoSwift

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

internal func pathFor(executable name: String) -> String? {
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
                sender.unsafeSend { _ in
                    returnCallback([], [], nil, "failed to find aws cli")
                }
                return
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
                
                var allObjects: [S3Object] = []
                var modifiedObjects: [S3Object] = []
                
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
                        
                        // to match existing logic in non-AWS version
                        if continuous == false || allObjects.count < 999 {
                            allObjects.append(
                                S3Object(keyPrefix: keyPrefix,
                                         key: s3Key,
                                         localFile: fileURL.path)
                            )
                        }
                        
                        localFilesByS3Key[s3Key] = localFile
                        localFilesSorted.append(localFile)
                    }
                }
                
                localFilesSorted.sort()
                
                // If our sorting of the local files and s3 bucket were perfect, then we could pick up
                // where the last file left off. However, given time drift of user devices it is entirely
                // possible that the sorting will leave gaps. To combat this, we allow up to one extra list
                // API call for continuous pulls.
                if continuous && localFilesSorted.count >= 999 {
                    let marker = localFilesSorted[localFilesSorted.count - 999].s3Key
                    arguments.append("--start-after")
                    arguments.append(marker)
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
                
                do {
                    try process.run()
                } catch {
                    return returnCallback([], [], nil, "failed to run aws cli: \(error)")
                }

                var error: String? = nil
                
                outputPipe.fileHandleForWriting.closeFile()
                
                let readHandle = outputPipe.fileHandleForReading
                let newline = UInt8(ascii: "\n")
                var pending = Data()
                
                func consume(line rawLine: String) {
                    let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard line.isEmpty == false else { return }
                    
                    if let object = S3Object.from(awsLog: line) {
                        allObjects.append(object)
                        modifiedObjects.append(object)
                    } else {
                        error = "failed to parse aws output: \(line)"
                    }
                }
                
                while true {
                    let chunk = readHandle.availableData
                    if chunk.isEmpty { break } // EOF
                    
                    pending.append(chunk)
                    
                    var parsedLines = 0
                    while let index = pending.firstIndex(of: newline) {
                        if let line = String(data: pending.subdata(in: pending.startIndex..<index),
                                             encoding: .utf8) {
                            consume(line: line)
                        }
                        pending.removeSubrange(pending.startIndex...index)
                        parsedLines += 1
                    }
                    
                    if parsedLines > 0 {
                        let total = allObjects.count
                        sender.unsafeSend { _ in
                            progressCallback(0, total, total)
                        }
                    }
                }
                
                // A final line with no trailing newline, if aws ended that way.
                if pending.isEmpty == false {
                    if let line = String(data: pending, encoding: .utf8) {
                        consume(line: line)
                    }
                    let total = allObjects.count
                    sender.unsafeSend { _ in
                        progressCallback(0, total, total)
                    }
                }
                
                process.waitUntilExit()
                
                guard process.terminationStatus == 0 else {
                    sender.unsafeSend { _ in
                        returnCallback([], [], nil, "aws cli failed code \(process.terminationStatus)")
                    }
                    return
                }
                
                sender.unsafeSend { _ in
                    returnCallback(allObjects, modifiedObjects, nil, error)
                }
                return
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
