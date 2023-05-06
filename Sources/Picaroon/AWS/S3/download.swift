import Foundation
import Flynn
import Hitch
import CryptoSwift

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct S3Credentials: Codable {
    public let url: String?
    
    public let accessKey: String
    public let secretKey: String
    public let baseDomain: String
    public let service: String
    public let region: String
    public let bucket: String
    
    public init(url: String?,
                accessKey: String,
                secretKey: String,
                baseDomain: String,
                service: String,
                region: String,
                bucket: String) {
        self.url = url
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.baseDomain = baseDomain
        self.service = service
        self.region = region
        self.bucket = bucket
    }
}

extension HTTPSession {
            
    internal func _beDownloadFromS3(credentials: S3Credentials,
                                    key: String,
                                    contentType: HttpContentType,
                                    _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) {
        let accessKey = credentials.accessKey
        let secretKey = credentials.secretKey
        let baseDomain = credentials.baseDomain
        let service = credentials.service
        let region = credentials.region
        let bucket = credentials.bucket
        
        let path = key.hasPrefix("/") ? key : "/" + key
                
        let date = Date().toRFC2822()
        
        var url = "https://{0}.{1}.{2}.{3}{4}" << [bucket, service, region, baseDomain, path]
        if let overrideUrl = credentials.url {
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
