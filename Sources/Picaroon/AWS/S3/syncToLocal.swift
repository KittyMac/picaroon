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
        return lhs.s3Key < rhs.s3Key
    }
    
    let name: String
    let path: String
    let s3Key: String
}

extension HTTPSession {
        
    internal func _beSyncToLocal(credentials: S3Credentials,
                                 keyPrefix: String,
                                 localDirectory: String,
                                 continuous: Bool,
                                 _ returnCallback: @escaping ([S3Object], [S3Object], String?, String?) -> Void) {
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
        var localFiles: [LocalFile] = []
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
                
                localFiles.append(LocalFile(name: fileURL.lastPathComponent,
                                            path: fileURL.path,
                                            s3Key: s3Key))
            }
        }
        
        localFiles.sort()
                
        var marker: String? = localFiles.last?.s3Key
        
        if continuous == false {
            marker = nil
        }
        
        HTTPSession.oneshot.beListAllKeysFromS3(credentials: credentials,
                                                keyPrefix: keyPrefix,
                                                marker: marker,
                                                self) { objects, continuationMarker, error in
            if let error = error { return returnCallback(objects, [], continuationMarker, error) }

            var mutableObjects = objects
            var lastError: String? = nil
            
            var modifiedObjects: [S3Object] = []
            
            // Remove any extra local files, remove any object we don't need to download
            for localFile in localFiles where marker == nil || localFile.s3Key > marker! {
                
                // Does this file exist on the s3?
                var existsOnTheS3 = false
                for object in mutableObjects {
                    if localFile.s3Key == object.key {
                        existsOnTheS3 = true
                        mutableObjects.removeOne(object)
                    }
                }
                
                // Doesn't exist on the s3, we should remove it
                if existsOnTheS3 == false {
                     try? FileManager.default.removeItem(atPath: localFile.path)
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
                returnCallback(objects, modifiedObjects, continuationMarker, lastError)
            }
        }
    }
    
}
