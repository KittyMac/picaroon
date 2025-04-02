import Foundation
import Flynn
import Hitch
import CryptoSwift

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

fileprivate struct LocalFile: Equatable, Comparable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.s3Key == rhs.s3Key
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        return Hitch(string: lhs.s3Key) < Hitch(string: rhs.s3Key)
    }
    
    let name: String
    let path: String
    let s3Key: String
}

extension HTTPSession {
        
    public func beSyncToLocal(credentials: S3Credentials,
                              keyPrefix: String,
                              localDirectory: String,
                              continuous: Bool,
                              priority: HTTPSessionPriority,
                              progressCallback: @escaping (Int, Int, Int) -> (),
                              _ sender: Actor,
                              _ returnCallback: @escaping ([S3Object], [S3Object], String?, String?) -> Void) {
        unsafeSend { _ in
            // Given an output directory, make its contents match the S3's content. This includes:
            // 1. removing any files which do not exist on the S3
            // 2. downloading any files which do not exist locally
            // 3. Assumes that the contents of the S3 are stored lexographically
            
            func makeRelativePath(key: String) -> String {
                var objectKey = key
                if objectKey.hasPrefix(keyPrefix) {
                    objectKey = objectKey.dropFirst(keyPrefix.count).description
                }
                if objectKey.hasPrefix("/") {
                    objectKey = objectKey.dropFirst(1).description
                }
                return objectKey
            }
            
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
                    
            var marker: String? = nil
            
            // If our sorting of the local files and s3 bucket were perfect, then we could pick up
            // where the last file left off. However, given time drift of user devices it is entirely
            // possible that the sorting will leave gaps. To combat this, we allow up to one extra list
            // API call for continuous pulls.
            if localFilesSorted.count >= 999 {
                marker = localFilesSorted[localFilesSorted.count - 999].s3Key
            }
            
            if continuous == false {
                marker = nil
            }
            
            var allObjects: [S3Object] = []
            var allObjectsByKey: [String: S3Object] = [:]
            var modifiedObjects: [S3Object] = []
            var lastError: String? = nil
            var continuationMarker: String? = nil
            
            let group = DispatchGroup()
            
            var downloadCount = 0
            var skippedCount = 0
            
            let processObjects: ([S3Object]) -> () = { objects in
                
                // Record the delta objects into all objects
                allObjects.append(contentsOf: objects)
                
                // Make a quick look up table of delta s3 objects by their key
                var mutableObjectsByKey: [String: S3Object] = [:]
                for object in objects {
                    allObjectsByKey[object.key] = object
                    if localFilesByS3Key[object.key] == nil {
                        mutableObjectsByKey[object.key] = object
                    } else {
                        skippedCount += 1
                    }
                }
                
                sender.unsafeSend { _ in
                    progressCallback(skippedCount, downloadCount, allObjects.count)
                }
                
                for object in mutableObjectsByKey.values {
                    group.enter()
                    HTTPSessionManager.shared.beNew(priority: priority, self) { session in
                        session.beDownloadFromS3(credentials: credentials,
                                                 key: object.key,
                                                 contentType: .any,
                                                 self) { data, source, response, error in
                            if let error = error {
                                lastError = error
                            }
                            
                            downloadCount += 1
                            
                            sender.unsafeSend { _ in
                                progressCallback(skippedCount, downloadCount, allObjects.count)
                            }
                            
                            if let data = data,
                               error == nil {
                                let objectKey = makeRelativePath(key: object.key)
                                
                                let fileUrl = localDirectoryUrl.appendingPathComponent(objectKey)
                                if (try? data.write(to: fileUrl)) == nil {
                                    // probably directory does not exist...
                                    try? FileManager.default.createDirectory(at: fileUrl.deletingLastPathComponent(),
                                                                             withIntermediateDirectories: true)
                                    try? data.write(to: fileUrl)
                                }
                                
                                // Update the modification date of the file to match the date of the s3 object
                                try? FileManager.default.setAttributes([
                                    FileAttributeKey.creationDate: object.modifiedDate,
                                ], ofItemAtPath: fileUrl.path)
                                
                                try? FileManager.default.setAttributes([
                                    FileAttributeKey.modificationDate: object.modifiedDate,
                                ], ofItemAtPath: fileUrl.path)
                                
                                modifiedObjects.append(object)
                            }
                            
                            group.leave()
                        }
                    }
                }
            }
            
            group.enter()
            self.beListAllKeysFromS3(credentials: credentials,
                                     keyPrefix: keyPrefix,
                                     marker: marker,
                                     priority: priority.increment(),
                                     progressCallback: processObjects,
                                     self) { objects, localContinuationMarker, error in
                if let error = error {
                    sender.unsafeSend { _ in
                        returnCallback(objects, [], localContinuationMarker, error)
                    }
                    return
                }
                continuationMarker = localContinuationMarker
                
                // Delete any local files we have which are not on the S3
                for localFile in localFilesSorted where marker == nil || localFile.s3Key > marker! {
                    if allObjectsByKey[localFile.s3Key] == nil {
                        try? FileManager.default.removeItem(atPath: localFile.path)
                    }
                }
                
                group.leave()
            }
            
            group.notify(actor: sender) {
                returnCallback(allObjects, modifiedObjects, continuationMarker, lastError)
            }
        }
        
        
    }
    
}
