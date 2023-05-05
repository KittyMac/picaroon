import Foundation
import Flynn
import Hitch
import CryptoSwift

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension HTTPSession {
        
    internal func _beListFromS3(accessKey: String?,
                                secretKey: String?,
                                region: String,
                                bucket: String,
                                keyPrefix: String,
                                marker: String?,
                                _ returnCallback: @escaping (Data?, HTTPURLResponse?, String?) -> Void) {
        guard let accessKey = accessKey ?? self.safeS3Key else {
            return returnCallback(nil, nil, "S3 key is nil")
        }
        guard let secretKey = secretKey ?? self.safeS3Secret else {
            return returnCallback(nil, nil, "S3 secret is nil")
        }
        
        let path = keyPrefix.hasPrefix("/") ? keyPrefix : "/" + keyPrefix
        
        // https://docs.aws.amazon.com/AmazonS3/latest/API/API_ListObjects.html
        let url = "https://{0}.{1}.{2}.amazonaws.com/" << [bucket, "s3", region]
        
        guard var components = URLComponents(string: url.description) else {
            returnCallback(nil, nil, "failed to create url components")
            return
        }
        
        if components.queryItems == nil {
            components.queryItems = []
        }
        
        if path != "/" {
            components.queryItems?.append(URLQueryItem(name: "prefix", value: path.dropFirst(1).description))
        }
        if let marker = marker {
            components.queryItems?.append(URLQueryItem(name: "marker", value: marker))
        }
        
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        
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
                                    bucket: bucket) {
            return returnCallback(nil, nil, error)
        }

        self.beRequest(request: request,
                       proxy: nil,
                       self) { data, response, error in
            returnCallback(data, response, error)
        }
    }
    
}

extension URLRequest {
    mutating func aws4(key: String,
                       secret: String,
                       service: String,
                       region: String,
                       bucket: String) -> String? {
        // https://docs.aws.amazon.com/IAM/latest/UserGuide/create-signed-request.html
        let hash: (Array<UInt8>, Array<UInt8>) -> Array<UInt8>? = { key, data in
            return try? HMAC(key: key, variant: .sha2(.sha256)).authenticate(data)
        }
        
        guard let method = httpMethod else { return "method is empty" }
        guard let url = url else { return "url is empty" }
        guard let host = url.host else { return "host is empty" }
        
        let query = url.query?.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? ""
        //let path = url.path.hasSuffix("/") ? url.path : url.path + "/"
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
        canonicalRequest.append(query)
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

