import Foundation
import Flynn
import Hitch
import CryptoSwift

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension HTTPSession {
    
    internal func _beSyncToLocal(credentials: S3Credentials,
                                 keyPrefix: String,
                                 localDirectory: String,
                                 _ returnCallback: @escaping ([S3Object], [S3Object], String?) -> Void) {
        // Given an output directory, make its contents match the S3's content. This includes:
        // 1. removing any files which do not exist on the S3
        // 2. downloading any files which do not exist locally
        
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
        
        HTTPSession.oneshot.beListAllKeysFromS3(credentials: credentials,
                                                keyPrefix: keyPrefix,
                                                self) { objects, error in
            if let error = error { return returnCallback(objects, [], error) }
            let localDirectoryUrl = URL(fileURLWithPath: localDirectory)
            
            var mutableObjects = objects
            var lastError: String? = nil
            
            var modifiedObjects: [S3Object] = []
                        
            // Remove any extra local files, remove any object we don't need to download
            if let enumerator = FileManager.default.enumerator(at: localDirectoryUrl,
                                                               includingPropertiesForKeys: [.isRegularFileKey],
                                                               options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let fileURL as URL in enumerator {
                    guard let resourceValues = try? fileURL.resourceValues(forKeys: Set([.isRegularFileKey])) else { continue }
                    guard resourceValues.isRegularFile == true else { continue }
                    
                    let filePath = fileURL.path
                    
                    // Does this file exist on the s3?
                    var existsOnTheS3 = false
                    for object in mutableObjects {
                        if filePath.hasSuffix(makeRelativePath(key: object.key)) {
                            existsOnTheS3 = true
                            mutableObjects.removeOne(object)
                        }
                    }
                    
                    // Doesn't exist on the s3, we should remove it
                    if existsOnTheS3 == false {
                        try? FileManager.default.removeItem(atPath: filePath)
                    }
                }
            }
            
            let group = DispatchGroup()
            
            for object in mutableObjects {
                group.enter()
                HTTPSessionManager.shared.beNew(self) { session in
                    session.beDownloadFromS3(credentials: credentials,
                                             key: object.key,
                                             contentType: .any,
                                             self) { data, response, error in
                        if let error = error {
                            lastError = error
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
            
            group.notify(actor: self) {
                returnCallback(objects, modifiedObjects, lastError)
            }
        }
    }
    
}
