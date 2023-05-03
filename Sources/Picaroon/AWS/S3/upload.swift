import Foundation
import Flynn
import Hitch
import CryptoSwift

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension HTTPSession {
    
    internal func _beSetCredentialsS3(key: String,
                                      secret: String) {
        safeS3Key = key
        safeS3Secret = secret
    }
    
    internal func _beUploadToS3(key: String?,
                                secret: String?,
                                domain: String?,
                                acl: String?,
                                storageType: String?,
                                bucket: String,
                                path: String,
                                contentType: HttpContentType,
                                body: Data,
                                _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) {
        guard let key = key ?? self.safeS3Key else {
            return returnCallback(nil, nil, "S3 key is nil")
        }
        guard let secret = secret ?? self.safeS3Secret else {
            return returnCallback(nil, nil, "S3 secret is nil")
        }
        
        let domain = domain ?? "s3.amazonaws.com"
        let acl = acl ?? "private"
        let storageType = storageType ?? "STANDARD"
        
        let date = Date().toRFC2822()
        
        let url = "https://{0}.{1}/{2}" << [bucket, domain, path]
        
        let auth: Hitch = Hitch("{0}\n\n{1}\n{2}\nx-amz-acl:{3}\nx-amz-storage-class:{4}\n{5}",
                                "PUT",
                                contentType.hitch,
                                date,
                                acl,
                                storageType,
                                "/{0}/{1}" << [bucket, path])
        
        guard let signature = try? HMAC(key: secret, variant: .sha1).authenticate(auth.dataNoCopy().bytes).toBase64() else {
            return returnCallback(nil, nil, "Failed to generate authorization token")
        }
        
        print("key: \(key)")
        print("secret: \(secret)")
        print("url: \(url)")
        print("auth: \(auth)")
        print("signature: \(signature)")
                    
        self.beRequest(url: url.toString(),
                       httpMethod: "PUT",
                       params: [:],
                       headers: [
                        "Date": date,
                        "Content-Type": contentType.hitch.description,
                        "x-amz-storage-class": storageType,
                        "x-amz-acl": acl,
                        "Authorization": "AWS \(key):\(signature)"
                       ],
                       cookies: nil,
                       proxy: nil,
                       body: body,
                       self) { data, response, error in
            returnCallback(data, response, error)
        }
    }
    
}
