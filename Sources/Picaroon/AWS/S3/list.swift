import Foundation
import Flynn
import Hitch
import CryptoSwift
import Studding

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct S3Object: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.key == rhs.key
    }
    
    public let keyPrefix: String
    
    public let key: String
    public let size: Int64
    public let modifiedDate: Date
    
    public var fileName: String {
        if key.hasPrefix(keyPrefix) {
            return key.dropFirst(keyPrefix.count).description.replacingOccurrences(of: "/", with: "_")
        }
        return key.replacingOccurrences(of: "/", with: "_")
    }
    
    public init?(xmlElement: XmlElement,
                 keyPrefix: String = "") {
        guard let key = xmlElement["Key"]?.text else { return nil }
        guard let size = xmlElement["Size"]?.text.toInt() else { return nil }
        guard let modifiedDate = xmlElement["LastModified"]?.text.description.date() else { return nil }
        self.key = key.toString()
        self.size = Int64(size)
        self.modifiedDate = modifiedDate
        self.keyPrefix = keyPrefix
    }
}

extension HTTPSession {
    
    internal func _beListFromS3(credentials: S3Credentials,
                                keyPrefix: String,
                                marker: String?,
                                _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) {
        let accessKey = credentials.accessKey
        let secretKey = credentials.secretKey
        let baseDomain = credentials.baseDomain
        let service = credentials.service
        let region = credentials.region
        let bucket = credentials.bucket
        
        let path = keyPrefix.hasPrefix("/") ? keyPrefix : "/" + keyPrefix
        
        // https://docs.aws.amazon.com/AmazonS3/latest/API/API_ListObjects.html
        var url = "https://{0}.{1}.{2}.{3}/" << [bucket, service, region, baseDomain]
        if let overrideUrl = credentials.url {
            url = "{0}/" << [overrideUrl, path]
        }
        
        var queryItems: [String: String] = [:]
        
        guard var components = URLComponents(string: url.description) else {
            returnCallback(nil, nil, "failed to create url components")
            return
        }
        
        if components.queryItems == nil {
            components.queryItems = []
        }
        
        if let marker = marker {
            queryItems["marker"] = marker
            components.queryItems?.append(URLQueryItem(name: "marker", value: marker))
        }
        if path != "/" {
            queryItems["prefix"] = path.dropFirst(1).description
            components.queryItems?.append(URLQueryItem(name: "prefix", value: path.dropFirst(1).description))
        }
        
        components.percentEncodedQuery = components.query?.percentEncoded()
        
        guard let url = components.url else {
            returnCallback(nil, nil, "failed to get components url")
            return
        }
        
        var request = URLRequest(url: url)
        
        request.httpMethod = "GET"
        request.httpBody = Data()
        //request.setValue(contentType.hitch.description, forHTTPHeaderField: "Content-Type")
        
        if let error = request.aws4(key: accessKey,
                                    secret: secretKey,
                                    service: "s3",
                                    region: region,
                                    bucket: bucket,
                                    queryItems: queryItems) {
            return returnCallback(nil, nil, error)
        }
        
        self.beRequest(request: request,
                       proxy: nil,
                       self) { data, response, error in
            returnCallback(data, response, error)
        }
    }
    
    internal func _beListAllKeysFromS3(credentials: S3Credentials,
                                       keyPrefix: String,
                                       _ returnCallback: @escaping ([S3Object], String?) -> Void) {
        var allObjects: [S3Object] = []
        
        func requestMore() {
            // Like beListFromS3(), but gives parsed results and will keep listing until all returns have been discovered
            HTTPSession.oneshot.beListFromS3(credentials: credentials,
                                             keyPrefix: keyPrefix,
                                             marker: allObjects.last?.key,
                                             self) { data, response, error in
                if let error = error { return returnCallback([], error) }
                guard let data = data else { return returnCallback([], "data is nil, unknown error listing bucket") }
                
                var isDone = false
                
                if let error: String? = Studding.parsed(data: data, { xml in
                    guard let xml = xml else { return "unable to parse xml" }
                    
                    isDone = xml["IsTruncated"]?.text != "true"
                    
                    for child in xml.children {
                        guard child.name == "Contents" else { continue }
                        guard let object = S3Object(xmlElement: child,
                                                    keyPrefix: keyPrefix) else {
                            return "failed to part Content"
                        }
                        guard object.key.hasSuffix("/") == false else { continue }
                        allObjects.append(object)
                    }
                    
                    return nil
                }) {
                    return returnCallback(allObjects, error)
                }
                
                if isDone {
                    return returnCallback(allObjects, nil)
                } else {
                    return requestMore()
                }
            }
        }
        
        requestMore()
    }
}

extension URLRequest {
    mutating func aws4(key: String,
                       secret: String,
                       service: String,
                       region: String,
                       bucket: String,
                       queryItems: [String: String]) -> String? {
        // https://docs.aws.amazon.com/IAM/latest/UserGuide/create-signed-request.html
        let hash: (Array<UInt8>, Array<UInt8>) -> Array<UInt8>? = { key, data in
            return try? HMAC(key: key, variant: .sha2(.sha256)).authenticate(data)
        }
        
        guard let method = httpMethod else { return "method is empty" }
        guard let url = url else { return "url is empty" }
        guard let host = url.host else { return "host is empty" }
        
        // Note: query parameters must be in the correct order (alphabetical)
        var query: String? = nil
        
        // The URL-encoded query string parameters, separated by ampersands (&). Percent-encode reserved characters, including the space character. Encode names and values separately.
        // If there are empty parameters, append the equals sign to the parameter name before encoding. After encoding, sort the parameters alphabetically by key name.
        // If there is no query string, use an empty string ("").
        //
        // example: marker=many%2Ffile1898.txt&amp;prefix=many%2F
        let sortedQueryKeys = queryItems.keys.sorted()
        if sortedQueryKeys.isEmpty == false {
            var queryString = ""
            for key in sortedQueryKeys {
                guard let value = queryItems[key] else { continue }
                guard let encodedKey = key.percentEncoded() else { continue }
                guard let encodedValue = value.percentEncoded() else { continue }
                queryString.append("\(encodedKey)=\(encodedValue)&")
            }
            if queryString.isEmpty == false {
                query = queryString.dropLast(1).description
            }
        }
        
        let path = url.path
        
        // *** Step 1: Create a canonical request
        // Header names must use lowercase characters, must appear in alphabetical order, and must be followed by a colon (:)
        var canonicalHeaders: [String: String] = [:]
        
        canonicalHeaders["host"] = host
        
        var contentHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        if let httpBody = httpBody {
            contentHash = httpBody.sha256().toHexString()
        }
        canonicalHeaders["x-amz-content-sha256"] = contentHash
        
        let date = Date().toISO8601Hitch().replace(occurencesOf: "-", with: "").replace(occurencesOf: ":", with: "")
        guard let dateShort = date.substring(0, 8) else {
            return "failed to create short date"
        }
        let dateString = date.toString()
        canonicalHeaders["x-amz-date"] = dateString
        
        var canonicalRequest: [String] = []
        // HTTPMethod
        canonicalRequest.append(method)
        // CanonicalUri
        canonicalRequest.append(path)
        // CanonicalQueryString
        canonicalRequest.append(query ?? "")
        // CanonicalHeaders
        for key in canonicalHeaders.keys.sorted() {
            guard let value = canonicalHeaders[key] else { continue }
            canonicalRequest.append("\(key):\(value)")
        }
        canonicalRequest.append("") // why?
        // SignedHeaders
        let signedHeaders = canonicalHeaders.keys.sorted().joined(separator: ";")
        canonicalRequest.append(signedHeaders)
        // HashedPayload
        canonicalRequest.append(contentHash)
        
        let canonicalRequestString = canonicalRequest.joined(separator: "\n")
        
        // *** Step 2: Create a hash of the canonical request
        let canonicalRequestHash = canonicalRequestString.description.sha256()
        
        // print("--------------------------")
        // print(canonicalRequestString)
        // print("-------")
        // print(canonicalRequestHash)
        // print("--------------------------")
        
        // *** Step 3: Create a string to sign
        let algorithm = "AWS4-HMAC-SHA256"
        let requestDateTime = dateString
        let credentialScope = [
            dateShort.description, region, service, "aws4_request"
        ].joined(separator: "/")
        
        let stringToSign = [
            algorithm,
            requestDateTime,
            credentialScope,
            canonicalRequestHash
        ].joined(separator: "\n")
        
        // print("--------------------------")
        // print(stringToSign)
        // print("--------------------------")
        //
        // print("--------------------------")
        // print("AWS4\(secret)")
        // print("--------------------------")
        
        // *** Step 4: Calculate the signature
        guard let kDate = hash("AWS4\(secret)".bytes, dateShort.description.bytes) else { return "failed to hash key" }
        guard let kRegion = hash(kDate, region.bytes) else { return "failed to hash region" }
        guard let kService = hash(kRegion, service.bytes) else { return "failed to hash service" }
        guard let kSigning = hash(kService, "aws4_request".bytes) else { return "failed to hash aws4_request" }
        
        guard let signature = hash(kSigning, stringToSign.bytes)?.toHexString() else { return "failed to hash signature" }
        
        let authorizationString = [
            "AWS4-HMAC-SHA256 Credential=\(key)/\(dateShort)/\(region)/\(service)/aws4_request",
            "SignedHeaders=\(signedHeaders)",
            "Signature=\(signature)"
        ].joined(separator: ", ")
        
        addValue(authorizationString, forHTTPHeaderField: "Authorization")
        
        for key in canonicalHeaders.keys.sorted() {
            guard key != "host" else { continue }
            guard let value = canonicalHeaders[key] else { continue }
            addValue(value, forHTTPHeaderField: key)
        }
        
        // print("--------------------------")
        // print(self.allHTTPHeaderFields)
        // print("--------------------------")
        
        return nil
    }
}

