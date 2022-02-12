import Flynn
import Foundation
import Hitch
import Spanker

/// Holds all of the information necessary to write an http response to a socket. Does not
/// copy the data it is given.
public struct HttpResponse {
    public static let sharedLastModifiedDate = Date()
    public static let sharedLastModifiedDateString = "\(sharedLastModifiedDate)".halfhitch()
    
    public static let internalServerError = HttpResponse(status: .internalServerError, type: .txt)
    public static let serviceUnavailable = HttpResponse(status: .serviceUnavailable, type: .txt)
    public static let badRequest = HttpResponse(status: .badRequest, type: .txt)

    
    private let status: HttpStatus;
    private let type: HttpContentType
    private let headers: [String]?
    private let encoding: String?
    private let lastModified: Date
    private let cacheMaxAge: Int
    
    private let payloads: [Payloadable]
    
    public init(status: HttpStatus,
                type: HttpContentType,
                headers: [String]? = nil,
                encoding: String? = nil,
                lastModified: Date = sharedLastModifiedDate,
                cacheMaxAge: Int = 0) {
        self.status = status
        self.type = type
        self.headers = headers
        self.encoding = encoding
        self.lastModified = lastModified
        self.cacheMaxAge = cacheMaxAge
        
        payloads = []
    }
    
    public init(status: HttpStatus,
                type: HttpContentType,
                payload: Data,
                headers: [String]? = nil,
                encoding: String? = nil,
                lastModified: Date = sharedLastModifiedDate,
                cacheMaxAge: Int = 0) {
        self.status = status
        self.type = type
        self.headers = headers
        self.encoding = encoding
        self.lastModified = lastModified
        self.cacheMaxAge = cacheMaxAge
        
        payloads = [payload]
    }
    
    public init(status: HttpStatus,
                type: HttpContentType,
                payload: Hitch,
                headers: [String]? = nil,
                encoding: String? = nil,
                lastModified: Date = sharedLastModifiedDate,
                cacheMaxAge: Int = 0) {
        self.status = status
        self.type = type
        self.headers = headers
        self.encoding = encoding
        self.lastModified = lastModified
        self.cacheMaxAge = cacheMaxAge
        
        payloads = [payload]
    }
    
    func isNew(_ request: HttpRequest) -> Bool {
        if let modifiedDate = request.ifModifiedSince {
            return HttpResponse.sharedLastModifiedDateString != modifiedDate
        }
        return true
    }
    
    func send(socket: Socket,
              userSession: UserSession?) {
        let combined = Hitch(capacity: 512)

        combined.append(status.string)
        combined.append("\r\n")

        if cacheMaxAge > 0 {
            combined.append("Cache-Control: public, max-age=\(cacheMaxAge)\r\n")
        }
        if let userSession = userSession {
            combined.append("Set-Cookie: \(Picaroon.userSessionCookie)=\(userSession.unsafeSessionUUID.prefix(36)); HttpOnly\r\n")
            for header in userSession.unsafeSessionHeaders {
                combined.append("\(header)\r\n")
            }
        }
        if let encoding = encoding {
            combined.append("Content-Encoding: \(encoding)\r\n")
        }

        if let headers = headers {
            for header in headers {
                combined.append("\(header)\r\n")
            }
        }
        
        combined.append("Server: Picaroon\r\n")
        combined.append("Last-Modified:\(lastModified)\r\n")
        combined.append("Connection: keep-alive\r\n")
        
        // Three possibilities:
        // 1. There is no payload content
        // 2. There is a single payload content ( return content normally )
        // 3. There are multiple payload contents ( return as multipart/form-data )
        var payloadCount = 0
        for payload in payloads {
            payloadCount += payload.count
        }
        
        // There is no payload, we're done!
        if payloads.count == 0 {
            combined.append("\r\n")
            socket.send(hitch: combined)
            return
        } else if payloads.count == 1 {
            let payload = payloads[0]
            
            combined.append("Content-Type: \(type.string)\r\n")
            combined.append("Content-Length:\(payloadCount)\r\n")
            combined.append("\r\n")
            
            socket.send(hitch: combined)
            
            payload.using { raw, count in
                socket.send(bytes: raw, count: count)
            }
            
            return
        } else {
            fatalError("to be implemented")
        }

        
        
        
        
        
    }
    
    
    /*
     GET / HTTP/1.1\r
     Content-Type: multipart/form-data\r
     Content-Length: 303\r
     \r
     ------WebKitFormBoundaryd9xBKq96rap8J36e\r
     Content-Disposition: form-data; name="type"\r
     \r
     UploadClassificationsFile\r
     ------WebKitFormBoundaryd9xBKq96rap8J36e\r
     Content-Disposition: form-data; name="file"; filename="test1.txt"\r
     Content-Type: text/plain\r
     \r
     test 1
     \r
     ------WebKitFormBoundaryd9xBKq96rap8J36e--\r
     */
    
    
    
    /*
    

    public static let sharedLastModifiedDate = Date()
    public static let sharedLastModifiedDateString = "\(sharedLastModifiedDate)".halfhitch()

    public static func isNew(_ request: HttpRequest) -> Bool {
        if let modifiedDate = request.ifModifiedSince {
            return sharedLastModifiedDateString != modifiedDate
        }
        return true
    }

    public static func asData(_ session: UserSession?,
                              _ status: HttpStatus,
                              _ type: HttpContentType,
                              _ payload: Data,
                              headers: [String]? = nil,
                              encoding: String? = nil,
                              lastModified: Date = sharedLastModifiedDate,
                              cacheMaxAge: Int = 0) -> Data {
        let combined = Hitch(capacity: payload.count + 500)

        combined.append(status.string)
        combined.append("\r\n")

        if cacheMaxAge > 0 {
            combined.append("Cache-Control: public, max-age=\(cacheMaxAge)\r\n")
        }
        if let session = session {
            combined.append("Set-Cookie: \(Picaroon.userSessionCookie)=\(session.unsafeSessionUUID.prefix(36)); HttpOnly\r\n")
            for header in session.unsafeSessionHeaders {
                combined.append("\(header)\r\n")
            }
        }
        if let encoding = encoding {
            combined.append("Content-Encoding: \(encoding)\r\n")
        }

        if let headers = headers {
            for header in headers {
                combined.append("\(header)\r\n")
            }
        }

        combined.append("Content-Type: \(type.string)\r\n")
        combined.append("Content-Length:\(payload.count)\r\n")
        combined.append("Connection: keep-alive\r\n")
        combined.append("Server: Picaroon\r\n")
        combined.append("Last-Modified:\(lastModified)\r\n\r\n")

        combined.append(payload)
        
        return combined.exportAsData()
    }

    public static func asData(_ session: UserSession?,
                              _ status: HttpStatus,
                              _ type: HttpContentType,
                              _ payload: String,
                              headers: [String]? = nil,
                              encoding: String? = nil,
                              lastModified: Date = sharedLastModifiedDate,
                              cacheMaxAge: Int = 0) -> Data {

        return asData(session,
                      status,
                      type,
                      payload.data(using: .utf8)!,
                      headers: headers,
                      encoding: encoding,
                      lastModified: lastModified,
                      cacheMaxAge: cacheMaxAge)
    }

    public static func asData(_ session: UserSession?,
                              _ status: HttpStatus,
                              _ type: HttpContentType) -> Data {
        return asData(session, status, type, status.string)
    }

    public static func asFile(_ session: UserSession?,
                              _ status: HttpStatus,
                              _ type: HttpContentType,
                              _ filename: String,
                              _ payload: Data) -> Data {
        return asData(session,
                      status,
                      type,
                      payload,
                      headers: [
            "Content-Transfer-Encoding: binary",
            "Content-Disposition: attachment; filename=\"\(filename)\""
        ])
    }
*/
}
