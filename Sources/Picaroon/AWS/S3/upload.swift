import Foundation
import Flynn
import Hitch
import CryptoSwift

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension HTTPSession {
    
    internal func _beSetCredentialsS3(accessKey: String,
                                      secretKey: String) {
        safeS3Key = accessKey
        safeS3Secret = secretKey
    }
    
    internal func _beUploadToS3(url overrideUrl: String?,
                                accessKey: String?,
                                secretKey: String?,
                                acl: String?,
                                storageType: String?,
                                region: String,
                                bucket: String,
                                key: String,
                                contentType: HttpContentType,
                                body: Data,
                                _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) {
        guard let accessKey = accessKey ?? self.safeS3Key else {
            return returnCallback(nil, nil, "S3 key is nil")
        }
        guard let secretKey = secretKey ?? self.safeS3Secret else {
            return returnCallback(nil, nil, "S3 secret is nil")
        }
        
        let path = key.hasPrefix("/") ? key : "/" + key
        
        let acl = acl ?? "private"
        let storageType = storageType ?? "STANDARD"
        
        let date = Date().toRFC2822()
        
        var url = "https://{0}.s3.{1}.amazonaws.com{2}" << [bucket, region, path]
        if let overrideUrl = overrideUrl {
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
                       proxy: nil,
                       body: body,
                       self) { data, response, error in
            returnCallback(data, response, error)
        }
    }
    
}
