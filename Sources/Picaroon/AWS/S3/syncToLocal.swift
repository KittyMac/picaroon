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
                                 _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) {
        // Given a prefix, sync the listed files from the S3 to a local directory
        /*
        // 0. Keep calling
        HTTPSession.oneshot.beListFromS3(credentials: credentials,
                                         keyPrefix: keyPrefix,
                                         marker: nil,
                                         self) { data, response, error in
            if let data = data,
               error == nil {
                let _ = Studding.parsed(data: data) { xml in
                    guard let xml = xml else {
                        sprint("DailyErrorLogs: unable to parse list bucket xml")
                        dailyPrefix.isDone = true
                        return false
                    }
                    
                    dailyPrefix.isDone = xml["IsTruncated"]?.text != "true"
                                            
                    for child in xml.children {
                        guard child.name.description == "Contents" else { continue }
                        guard let key = child["Key"]?.text.toString() else { continue }
                        guard key.hasSuffix(".log") else { continue }
                        dailyPrefix.marker = key
                        dailyPrefix.allKeys.append(key)
                    }
                    return true
                }
            } else {
                sprint("DailyErrorLogs: \(error ?? "listing bucket failed for unknown reason")")
                dailyPrefix.isDone = true
            }
            
            self.bePerformProcess(dailyPrefix: dailyPrefix)
        }
        */
        
    }
    
}
