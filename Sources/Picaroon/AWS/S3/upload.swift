// flynn:ignore Weak Timer Violation

import Foundation
import Flynn
import Hitch
import CryptoSwift

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension HTTPSession {
    
    private func performUploadToS3(credentials: S3Credentials,
                                   acl: String?,
                                   storageType: String?,
                                   key: String,
                                   contentType: HttpContentType,
                                   body: Data,
                                   retry: Int,
                                   _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) {
        let accessKey = credentials.accessKey
        let secretKey = credentials.secretKey
        let baseDomain = credentials.baseDomain
        let service = credentials.service
        let region = credentials.region
        let bucket = credentials.bucket

        let path = (key.hasPrefix("/") ? key : "/" + key).replacingOccurrences(of: " ", with: "+")
        
        let acl = acl ?? "private"
        let storageType = storageType ?? "STANDARD"
        
        let date = NTP.date().toRFC2822()
        
        var url = "https://{0}.{1}.{2}.{3}{4}" << [bucket, service, region, baseDomain, path]
        if let overrideUrl = credentials.url {
            url = "{0}{1}" << [overrideUrl, path]
        }

        let auth: Hitch = Hitch("{0}\n\n{1}\n{2}\nx-amz-acl:{3}\nx-amz-storage-class:{4}\n{5}",
                                "PUT",
                                contentType.hitch,
                                date,
                                acl,
                                storageType,
                                "/{0}{1}" << [bucket, path])
        
        guard let signature = try? HMAC(key: secretKey, variant: .sha1).authenticate(auth.dataNoCopy().bytes).toBase64() else {
            return returnCallback(nil, nil, "Failed to generate authorization token")
        }
                            
        self.beRequest(url: url.toString(),
                       httpMethod: "PUT",
                       params: [:],
                       headers: [
                        "Date": date,
                        "Content-Type": contentType.hitch.description,
                        "x-amz-storage-class": storageType,
                        "x-amz-acl": acl,
                        "Authorization": "AWS \(accessKey):\(signature)"
                       ],
                       cookies: nil,
                       timeoutRetry: 10,
                       proxy: nil,
                       body: body,
                       self) { data, response, error in
            if error == "http 403" || error == "http 503" {
                NTP.reset()
                if retry > 0 {
                    let actor = Actor()
                    Flynn.Timer(timeInterval: 3.0, immediate: false, repeats: false, actor) { timer in
                        HTTPSessionManager.shared.beNew(actor) { session in
                            // fputs("aws upload http 403, retrying \(retry)\n", stderr)
                            session.performUploadToS3(credentials: credentials,
                                                      acl: acl,
                                                      storageType: storageType,
                                                      key: key,
                                                      contentType: contentType,
                                                      body: body,
                                                      retry: retry - 1,
                                                      returnCallback)
                        }
                    }
                    return
                }
            }
            
            returnCallback(data, response, error)
        }
    }
        
    internal func _beUploadToS3(credentials: S3Credentials,
                                acl: String?,
                                storageType: String?,
                                key: String,
                                contentType: HttpContentType,
                                body: Data,
                                _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) {
        performUploadToS3(credentials: credentials,
                          acl: acl,
                          storageType: storageType,
                          key: key,
                          contentType: contentType,
                          body: body,
                          retry: 3,
                          returnCallback)
    }
    
}
