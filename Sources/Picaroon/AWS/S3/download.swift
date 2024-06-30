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

extension URL {
    var attributes: [FileAttributeKey: Any]? {
        return try? FileManager.default.attributesOfItem(atPath: path)
    }

    var fileSize: UInt64 {
        return attributes?[.size] as? UInt64 ?? UInt64(0)
    }

    var fileSizeString: String {
        return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }

    var creationDate: Date? {
        return attributes?[.creationDate] as? Date
    }

    var modificationDate: Date? {
        return attributes?[.modificationDate] as? Date
    }
}

public enum HttpSource {
    case cache
    case notModified
    case network
}

extension HTTPSession {
    
    private func performDownloadFromS3(credentials: S3Credentials,
                                       key: String,
                                       contentType: HttpContentType,
                                       retry: Int,
                                       _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) {
        let accessKey = credentials.accessKey
        let secretKey = credentials.secretKey
        let baseDomain = credentials.baseDomain
        let service = credentials.service
        let region = credentials.region
        let bucket = credentials.bucket
        
        let path = key.hasPrefix("/") ? key : "/" + key
                
        let date = NTP.date().toRFC2822()
        
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
                       timeoutRetry: 10,
                       proxy: nil,
                       body: nil,
                       self) { data, response, error in
            if error == "http 403" || error == "http 503" {
                NTP.reset()
                if retry > 0 {
                    Flynn.Timer(timeInterval: 3.0, immediate: false, repeats: false, self) { [weak self] timer in
                        guard let self = self else { return }
                        // fputs("aws download http 403, retrying \(retry)\n", stderr)
                        self.performDownloadFromS3(credentials: credentials,
                                                   key: key,
                                                   contentType: contentType,
                                                   retry: retry - 1,
                                                   returnCallback)
                    }
                    return
                }
            }
            
            returnCallback(data, response, error)
        }
    }
            
    internal func _beDownloadFromS3(credentials: S3Credentials,
                                    key: String,
                                    contentType: HttpContentType,
                                    _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) {
        return performDownloadFromS3(credentials: credentials,
                                     key: key,
                                     contentType: contentType,
                                     retry: 3,
                                     returnCallback)
    }
    
    
    private func performDownloadFromS3(toFilePath: String,
                                       credentials: S3Credentials,
                                       key: String,
                                       contentType: HttpContentType,
                                       cacheTime: TimeInterval,
                                       retry: Int,
                                       _ returnCallback: @escaping (Data?, HttpSource?, HTTPURLResponse?, String?) -> Void) {
        // Download data smartly from S3:
        // - if file does not exit at path, then downloads, store it there, and set modification date
        // - if file exists at path and it was modified less than cacheTime ago, then just return the cached data
        // - if file exists at path and it is older than cacheTime ago, make S3 request with If-Modified-Since header
        //  - if response is http 304, load an return cached data
        //  - if reponse is success, save new data to cache location and set modification date
        
        let accessKey = credentials.accessKey
        let secretKey = credentials.secretKey
        let baseDomain = credentials.baseDomain
        let service = credentials.service
        let region = credentials.region
        let bucket = credentials.bucket
        
        let path = key.hasPrefix("/") ? key : "/" + key
                
        let date = NTP.date().toRFC2822()
        
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
            return returnCallback(nil, nil, nil, "Failed to generate authorization token")
        }
        
        var headers: [String: String] = [
            "Date": date,
            "Content-Type": contentType.hitch.description,
            "Authorization": "AWS \(accessKey):\(signature)"
        ]
        
        let requestDate = Date()
        
        let fileUrl = URL(fileURLWithPath: toFilePath)
        if let fileModificationDate = fileUrl.modificationDate ?? fileUrl.creationDate {
            headers["If-Modified-Since"] = fileModificationDate.toRFC2822()
            
            if abs(fileModificationDate.timeIntervalSinceNow) < cacheTime,
               let data = try? Data(contentsOf: fileUrl) {
                return returnCallback(data, .cache, nil, nil)
            }
        }
        
        self.beRequest(url: url.toString(),
                       httpMethod: "GET",
                       params: [:],
                       headers: headers,
                       cookies: nil,
                       timeoutRetry: 10,
                       proxy: nil,
                       body: nil,
                       self) { data, response, error in
            
            if error == "http 403" || error == "http 503" {
                NTP.reset()
                if retry > 0 {
                    Flynn.Timer(timeInterval: 3.0, immediate: false, repeats: false, self) { [weak self] timer in
                        guard let self = self else { return }
                        // fputs("aws download http 403, retrying \(retry)\n", stderr)
                        self.performDownloadFromS3(toFilePath: toFilePath,
                                                   credentials: credentials,
                                                   key: key,
                                                   contentType: contentType,
                                                   cacheTime: cacheTime,
                                                   retry: retry - 1,
                                                   returnCallback)
                    }
                    return
                }
            }
            
            if error == "http 304" {
                if let data = try? Data(contentsOf: fileUrl) {
                    // Update the modification date of the file to match the date we sent
                    // We do this so that we can piggy back on the date for caching purposes
                    try? FileManager.default.setAttributes([
                        FileAttributeKey.creationDate: requestDate,
                    ], ofItemAtPath: fileUrl.path)
                    
                    try? FileManager.default.setAttributes([
                        FileAttributeKey.modificationDate: requestDate,
                    ], ofItemAtPath: fileUrl.path)
                    
                    // file has not changed, we can return the data from disk
                    return returnCallback(data, .notModified, response, nil)
                }
                return returnCallback(nil, nil, response, "http 304 but cached file is missing")
            }
            
            if error == nil,
               let data = data,
               let lastModifiedString = response?.allHeaderFields["Last-Modified"] as? String,
               let lastModifiedDate = lastModifiedString.fromRFC2822() {
               
                // we received data; save it to disk and set its modification date
                try? data.write(to: fileUrl)
                
                // Update the modification date of the file to match the date of the s3 object
                try? FileManager.default.setAttributes([
                    FileAttributeKey.creationDate: lastModifiedDate,
                ], ofItemAtPath: fileUrl.path)
                
                try? FileManager.default.setAttributes([
                    FileAttributeKey.modificationDate: lastModifiedDate,
                ], ofItemAtPath: fileUrl.path)
            }
            
            return returnCallback(data, .network, response, error)
        }
    }
    
    internal func _beDownloadFromS3(toFilePath: String,
                                    credentials: S3Credentials,
                                    key: String,
                                    contentType: HttpContentType,
                                    cacheTime: TimeInterval,
                                    _ returnCallback: @escaping (Data?, HttpSource?, HTTPURLResponse?, String?) -> Void) {
        performDownloadFromS3(toFilePath: toFilePath,
                              credentials: credentials,
                              key: key,
                              contentType: contentType,
                              cacheTime: cacheTime,
                              retry: 3,
                              returnCallback)
    }
    
}
