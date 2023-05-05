import Foundation
import Flynn
import Hitch
import CryptoSwift

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension HTTPSession {
        
    internal func _beDownloadFromS3(url overrideUrl: String?,
                                    accessKey: String?,
                                    secretKey: String?,
                                    region: String,
                                    bucket: String,
                                    key: String,
                                    contentType: HttpContentType,
                                    _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) {
        guard let accessKey = accessKey ?? self.safeS3Key else {
            return returnCallback(nil, nil, "S3 key is nil")
        }
        guard let secretKey = secretKey ?? self.safeS3Secret else {
            return returnCallback(nil, nil, "S3 secret is nil")
        }
        
        let path = key.hasPrefix("/") ? key : "/" + key
                
        let date = Date().toRFC2822()
        
        var url = "https://{0}.s3.{1}.amazonaws.com{2}" << [bucket, region, path]
        if let overrideUrl = overrideUrl {
            url = "{0}{1}" << [overrideUrl, path]
        }
        
        let auth: Hitch = Hitch("{0}\n\n{1}\n{2}\n{3}",
                                "GET",
                                contentType.hitch,
                                date,
                                "/{0}{1}" << [bucket, path])
        
        guard let signature = try? HMAC(key: secretKey, variant: .sha1).authenticate(auth.dataNoCopy().bytes).toBase64() else {
            return returnCallback(nil, nil, "Failed to generate authorization token")
        }
                    
        self.beRequest(url: url.toString(),
                       httpMethod: "GET",
                       params: [:],
                       headers: [
                        "Date": date,
                        "Content-Type": contentType.hitch.description,
                        "Authorization": "AWS \(accessKey):\(signature)"
                       ],
                       cookies: nil,
                       proxy: nil,
                       body: nil,
                       self) { data, response, error in
            returnCallback(data, response, error)
        }
    }
    
}
