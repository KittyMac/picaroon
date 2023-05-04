import Foundation
import Flynn
import Hitch
import CryptoSwift

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension HTTPSession {
        
    internal func _beDownloadFromS3(key: String?,
                                    secret: String?,
                                    region: String,
                                    bucket: String,
                                    path: String,
                                    contentType: HttpContentType,
                                    _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) {
        guard path.hasPrefix("/") else {
            return returnCallback(nil, nil, "path does not start at root")
        }
        guard let key = key ?? self.safeS3Key else {
            return returnCallback(nil, nil, "S3 key is nil")
        }
        guard let secret = secret ?? self.safeS3Secret else {
            return returnCallback(nil, nil, "S3 secret is nil")
        }
                
        let date = Date().toRFC2822()
        
        let url = "https://{0}.s3-{1}.amazonaws.com{2}" << [bucket, region, path]
        
        let auth: Hitch = Hitch("{0}\n\n{1}\n{2}\n{3}",
                                "GET",
                                contentType.hitch,
                                date,
                                "/{0}{1}" << [bucket, path])
        
        guard let signature = try? HMAC(key: secret, variant: .sha1).authenticate(auth.dataNoCopy().bytes).toBase64() else {
            return returnCallback(nil, nil, "Failed to generate authorization token")
        }
                    
        self.beRequest(url: url.toString(),
                       httpMethod: "GET",
                       params: [:],
                       headers: [
                        "Date": date,
                        "Content-Type": contentType.hitch.description,
                        "Authorization": "AWS \(key):\(signature)"
                       ],
                       cookies: nil,
                       proxy: nil,
                       body: nil,
                       self) { data, response, error in
            returnCallback(data, response, error)
        }
    }
    
}
