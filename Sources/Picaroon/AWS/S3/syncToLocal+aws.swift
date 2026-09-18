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
            
            S3CommandRunner.next().beSyncToLocal(executable: path,
                                                 credentials: credentials,
                                                 keyPrefix: keyPrefix,
                                                 localDirectory: localDirectory,
                                                 continuous: continuous,
                                                 { count in
                                                     sender.unsafeSend { _ in
                                                         progressCallback(0, count, count)
                                                     }
                                                 },
                                                 sender,
                                                 returnCallback)
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
