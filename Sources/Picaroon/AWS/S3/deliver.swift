// flynn:ignore Weak Timer Violation
// flynn:ignore Access Level Violation: Behaviors must wrap their contents in a call to unsafeSend()

import Foundation
import Flynn
import Hitch
import CryptoSwift

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension HTTPSession {
    
    @discardableResult
    public func beDeliverToS3(credentials: S3Credentials,
                              acl: String?,
                              storageType: String?,
                              key: String,
                              contentType: HttpContentType,
                              body: Data,
                              _ sender: Actor,
                              _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) -> Self {
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
        
        guard let signature = try? HMAC(key: secretKey, variant: .sha1).authenticate(auth.dataNoCopy().byteArray).toBase64() else {
            returnCallback(nil, nil, "Failed to generate authorization token")
            return unsafeSend ({ thenPtr in
                self.safeThen(thenPtr)
            })
        }
        
        var unsafeThenPtr: UInt64 = 0
        let group = DispatchGroup()
        
        group.enter()
        HTTPDeliveryManager.shared.beDeliver(url: url.toString(),
                                             httpMethod: "PUT",
                                             params: [:],
                                             headers: [
                                                "Date": date,
                                                "Content-Type": contentType.hitch.description,
                                                "x-amz-storage-class": storageType,
                                                "x-amz-acl": acl,
                                                "Authorization": "AWS \(accessKey):\(signature)"
                                            ],
                                             proxy: nil,
                                             body: body,
                                             sender) { data, response, error in
            returnCallback(data, response, error)
            group.wait()
            self.safeThen(unsafeThenPtr)
        }
        return self.unsafeSend ({ thenPtr in
            unsafeThenPtr = thenPtr
            group.leave()
        })
    }
    
    @discardableResult
    public func doDeliverToS3(credentials: S3Credentials,
                              acl: String?,
                              storageType: String?,
                              key: String,
                              contentType: HttpContentType,
                              body: Data,
                              _ sender: Actor,
                              _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) -> Self {
        return beDeliverToS3(credentials: credentials,
                             acl: acl,
                             storageType: storageType,
                             key: key,
                             contentType: contentType,
                             body: body,
                             sender,
                             returnCallback)
    }
    
}
