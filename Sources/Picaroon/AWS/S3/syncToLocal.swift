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
                                 _ returnCallback: @escaping (Int, String?) -> Void) {
        // Given an output directory, make its contents match the S3's content. This includes:
        // 1. removing any files which do not exist on the S3
        // 2. downloading any files which do not exist locally
        
        HTTPSession.oneshot.beListAllKeysFromS3(credentials: credentials,
                                            keyPrefix: keyPrefix,
                                                self) { objects, error in
            if let error = error { return returnCallback(0, error) }
            let localDirectoryUrl = URL(fileURLWithPath: localDirectory)
            
            var mutableObjects = objects
            var lastError: String? = nil
            
            var filesChanged = 0
            
            // Ensure the output directory exists
            try? FileManager.default.createDirectory(at: localDirectoryUrl,
                                                     withIntermediateDirectories: true)
            
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
                    for object in mutableObjects where filePath.hasSuffix(object.key) {
                        existsOnTheS3 = true
                        mutableObjects.removeOne(object)
                    }
                    
                    // Doesn't exist on the s3, we should remove it
                    if existsOnTheS3 == false {
                        filesChanged += 1
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
                            let fileUrl = localDirectoryUrl.deletingLastPathComponent().appendingPathComponent(object.key)
                            if (try? data.write(to: fileUrl)) == nil {
                                // probably directory does not exist...
                                try? FileManager.default.createDirectory(at: fileUrl.deletingLastPathComponent(),
                                                                         withIntermediateDirectories: true)
                                try? data.write(to: fileUrl)
                            }
                            filesChanged += 1
                        }
                        
                        group.leave()
                    }
                }
            }
            
            group.notify(actor: self) {
                returnCallback(filesChanged, lastError)
            }
        }
    }
    
}
