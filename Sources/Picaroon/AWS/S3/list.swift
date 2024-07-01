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
            var withoutPrefix = key.dropFirst(keyPrefix.count)
            if withoutPrefix.hasPrefix("/") {
                withoutPrefix = withoutPrefix.dropFirst(1)
            }
            return withoutPrefix.description.replacingOccurrences(of: "/", with: "_")
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
                                _ returnCallback: @escaping ([S3Object], String?, Bool, String?) -> Void) {
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
            returnCallback([], nil, false, "failed to create url components")
            return
        }
        
        // At this point components.queryItems contains the queries embedded in the url
        // in an percent unescaped fashion. components.url will, by default, attempt to
        // percent escape the query string. However, the percent escaping it performs does
        // not appear to be standard. Specifically, things like "/" and "+" do not get
        // escaped. Some service (like Amazon S3) require that the queries be properly
        // percent escaped.
        // To work around this, we generate an array of unescaped query items, then we
        // manually percent escape each name and value using a custom percentEncoded method.
        // Finally override components.percentEncodedQuery with components.query which
        // will be the correct string with unescaped &name=value while "name" and "value"
        // are escaped.
        var unescapedQueryItems: [URLQueryItem] = []
        if let originalQueryItems = components.queryItems {
            for originalQueryItem in originalQueryItems {
                unescapedQueryItems.append(originalQueryItem)
            }
        }
        
        if let marker = marker {
            queryItems["marker"] = marker
            unescapedQueryItems.append(URLQueryItem(name: "marker",
                                                    value: marker))
        }
        if path != "/" {
            let value = path.dropFirst(1).description
            queryItems["prefix"] = value
            unescapedQueryItems.append(URLQueryItem(name: "prefix",
                                                    value: value))
        }
        
        if unescapedQueryItems.count > 0 {
            components.queryItems = []
            for unescapedQueryItem in unescapedQueryItems {
                components.queryItems?.append(URLQueryItem(name: unescapedQueryItem.name.percentEncoded() ?? unescapedQueryItem.name,
                                                           value: unescapedQueryItem.value?.percentEncoded() ?? unescapedQueryItem.value))
            }
        }
        
        components.percentEncodedQuery = components.query

        guard let url = components.url else {
            returnCallback([], nil, false, "failed to get components url")
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
            return returnCallback([], nil, false, error)
        }
        
        self.beRequest(request: request,
                       timeoutRetry: 10,
                       proxy: nil,
                       self) { data, response, error in
            
            
            if let error = error { return returnCallback([], nil, false, error) }
            guard let data = data else { return returnCallback([], nil, false, "data is nil, unknown error listing bucket") }
            
            var isDone = false
            var allObjects: [S3Object] = []
            
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
                return returnCallback(allObjects, allObjects.last?.key ?? marker, isDone, error)
            }
            
            returnCallback(allObjects, allObjects.last?.key ?? marker, isDone, nil)
        }
    }
    
    internal func _beListAllKeysFromS3(credentials: S3Credentials,
                                       keyPrefix: String,
                                       marker: String?,
                                       priority: HTTPSessionPriority,
                                       _ returnCallback: @escaping ([S3Object], String?, String?) -> Void) {
        var allObjects: [S3Object] = []
        
        func requestMore(marker: String?) {
            // Like beListFromS3(), but gives parsed results and will keep listing until all returns have been discovered
            HTTPSessionManager.shared.beNew(priority: priority, self) { session in
                session.beListFromS3(credentials: credentials,
                                     keyPrefix: keyPrefix,
                                     marker: marker,
                                     self) { moreObjects, continuationMarker, isDone, error in
                    
                    if let error = error { return returnCallback(allObjects, continuationMarker, error) }
                    
                    allObjects.append(contentsOf: moreObjects)
                    
                    if isDone {
                        return returnCallback(allObjects, continuationMarker, nil)
                    } else {
                        return requestMore(marker: continuationMarker)
                    }
                }
            }
        }
        
        requestMore(marker: marker)
    }
    
    public func beListAllKeysFromS3(credentials: S3Credentials,
                                    keyPrefix: String,
                                    marker: String?,
                                    priority: HTTPSessionPriority,
                                    progressCallback: @escaping ([S3Object]) -> Void,
                                    _ sender: Actor,
                                    _ returnCallback: @escaping ([S3Object], String?, String?) -> Void) {
        unsafeSend { _ in
            var allObjects: [S3Object] = []
            
            func requestMore(marker: String?) {
                // Like beListFromS3(), but gives parsed results and will keep listing until all returns have been discovered
                HTTPSessionManager.shared.beNew(priority: priority, self) { session in
                    session.beListFromS3(credentials: credentials,
                                         keyPrefix: keyPrefix,
                                         marker: marker,
                                         self) { moreObjects, continuationMarker, isDone, error in
                        allObjects.append(contentsOf: moreObjects)
                        
                        sender.unsafeSend { _ in
                            progressCallback(moreObjects)
                            if isDone || error != nil {
                                returnCallback(allObjects, continuationMarker, error)
                            }
                        }
                        
                        if isDone == false && error == nil {
                            return requestMore(marker: continuationMarker)
                        }
                    }
                }
            }
            
            requestMore(marker: marker)
        }
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
        
        let date = NTP.date().toISO8601Hitch().replace(occurencesOf: "-", with: "").replace(occurencesOf: ":", with: "")
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

