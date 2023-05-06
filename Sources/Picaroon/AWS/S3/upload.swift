import Foundation
import Flynn
import Hitch
import CryptoSwift

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension HTTPSession {
        
    internal func _beUploadToS3(credentials: S3Credentials,
                                acl: String?,
                                storageType: String?,
                                key: String,
                                contentType: HttpContentType,
                                body: Data,
                                _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) {
        let accessKey = credentials.accessKey
        let secretKey = credentials.secretKey
        let baseDomain = credentials.baseDomain
        let service = credentials.service
        let region = credentials.region
        let bucket = credentials.bucket

        let path = key.hasPrefix("/") ? key : "/" + key
        
        let acl = acl ?? "private"
        let storageType = storageType ?? "STANDARD"
        
        let date = Date().toRFC2822()
        
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
                       proxy: nil,
                       body: body,
                       self) { data, response, error in
            returnCallback(data, response, error)
        }
    }
    
}
