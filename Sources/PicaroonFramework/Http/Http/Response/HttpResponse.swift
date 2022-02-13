import Flynn
import Foundation
import Hitch
import Spanker

private let hitchContentDispositionFormDataWithName = "Content-Disposition:form-data;name=\"".hitch()
private let hitchContentDispositionFormData = "Content-Disposition:form-data\r\n".hitch()
private let hitchContentLength = "Content-Length:".hitch()
private let hitchNewLine = "\r\n".hitch()
private let hitchCacheControl = "Cache-Control:public, max-age=".hitch()

private let hitchSetCookie1 = "Set-Cookie:".hitch()
private let hitchSetCookie2 = "; HttpOnly\r\n".hitch()

private let hitchContentEncoding = "Content-Encoding:".hitch()
private let hitchLastModified = "Last-Modified:".hitch()
private let hitchKeepAlive = "Connection:keep-alive\r\n".hitch()
private let hitchContentType = "Content-Type:".hitch()
private let hitchMultipartBoundary = "------WebKitFormBoundaryd9xBKq96rap8J36e\r\n".hitch()

protocol SocketSendable {
    @discardableResult func send(hitch: Hitch) -> Int
    @discardableResult func send(data: Data) -> Int
    @discardableResult func send(bytes: UnsafePointer<UInt8>?,
                                 count: Int) -> Int
}

extension Socket: SocketSendable {
    
}

/// Holds all of the information necessary to write an http response to a socket. Does not
/// copy the data it is given.
public class HttpResponse {
    
    public static let sharedLastModifiedDate = Date()
    public static let sharedLastModifiedDateHitch = "\(sharedLastModifiedDate)".hitch()
    public static let sharedLastModifiedDateHalfHitch = "\(sharedLastModifiedDate)".halfhitch()
    
    private let status: HttpStatus;
    private let type: HttpContentType
    private let headers: [Hitchable]?
    private let encoding: Hitchable?
    private let lastModified: Hitch
    private let cacheMaxAge: Int
    
    private let payload: Payloadable?
    private let multipart: [HttpResponse]?
    private let multipartName: Hitch?
    
    func postInit() {

    }
    
    public init(httpResponse: HttpResponse,
                multipartName: Hitch? = nil) {
        self.status = httpResponse.status
        self.type = httpResponse.type
        self.headers = httpResponse.headers
        self.encoding = httpResponse.encoding
        self.lastModified = httpResponse.lastModified
        self.cacheMaxAge = httpResponse.cacheMaxAge
        self.payload = httpResponse.payload
        self.multipart = httpResponse.multipart
        self.multipartName = multipartName
        
        postInit()
    }
    
    public init(multipart: [HttpResponse],
                headers: [Hitchable]? = nil,
                encoding: Hitchable? = nil,
                lastModified: Date? = nil,
                cacheMaxAge: Int = 0) {
        self.status = .ok
        self.type = .txt
        self.headers = headers
        self.encoding = encoding
        self.lastModified = lastModified?.description.hitch() ?? HttpResponse.sharedLastModifiedDateHitch
        self.cacheMaxAge = cacheMaxAge
        self.payload = nil
        self.multipart = multipart
        self.multipartName = nil
        
        postInit()
    }
    
    public init(status: HttpStatus,
                type: HttpContentType,
                multipartName: Hitch? = nil,
                headers: [Hitchable]? = nil,
                encoding: Hitchable? = nil,
                lastModified: Date? = nil,
                cacheMaxAge: Int = 0) {
        self.status = status
        self.type = type
        self.headers = headers
        self.encoding = encoding
        self.lastModified = lastModified?.description.hitch() ?? HttpResponse.sharedLastModifiedDateHitch
        self.cacheMaxAge = cacheMaxAge
        self.payload = nil
        self.multipart = nil
        self.multipartName = multipartName
        
        postInit()
    }
    
    public init(status: HttpStatus,
                type: HttpContentType,
                payload: Payloadable,
                multipartName: Hitch? = nil,
                headers: [Hitchable]? = nil,
                encoding: Hitchable? = nil,
                lastModified: Date? = nil,
                cacheMaxAge: Int = 0) {
        self.status = status
        self.type = type
        self.headers = headers
        self.encoding = encoding
        self.lastModified = lastModified?.description.hitch() ?? HttpResponse.sharedLastModifiedDateHitch
        self.cacheMaxAge = cacheMaxAge
        self.payload = payload
        self.multipart = nil
        self.multipartName = multipartName
        
        postInit()
    }
    
    public init(status: HttpStatus,
                type: HttpContentType,
                payload: Hitch,
                multipartName: Hitch? = nil,
                headers: [Hitchable]? = nil,
                encoding: Hitchable? = nil,
                lastModified: Date? = nil,
                cacheMaxAge: Int = 0) {
        self.status = status
        self.type = type
        self.headers = headers
        self.encoding = encoding
        self.lastModified = lastModified?.description.hitch() ?? HttpResponse.sharedLastModifiedDateHitch
        self.cacheMaxAge = cacheMaxAge
        self.payload = payload
        self.multipart = nil
        self.multipartName = multipartName
        
        postInit()
    }
    
    @inlinable @inline(__always)
    func isNew(_ request: HttpRequest) -> Bool {
        if let modifiedDate = request.ifModifiedSince {
            return HttpResponse.sharedLastModifiedDateHalfHitch != modifiedDate
        }
        return true
    }
    
    func multipartCount() -> Int {
        guard let payload = payload else { return 0 }
        return 128 + payload.count
    }
    
    func multipartAppend(_ combined: Hitch) {
        guard let payload = payload else { return }
        if let multipartName = multipartName {
            combined.append(hitchContentDispositionFormDataWithName)
            combined.append(multipartName)
            combined.append(.doubleQuote)
            combined.append(hitchNewLine)
        } else {
            combined.append(hitchContentDispositionFormData)
        }
        combined.append(hitchContentLength)
        combined.append(number: payload.count)
        combined.append(hitchNewLine)
        
        if let encoding = encoding {
            combined.append(hitchContentEncoding)
            combined.append(encoding)
            combined.append(hitchNewLine)
        }
        
        combined.append(hitchNewLine)
        payload.using { bytes, count in
            guard let bytes = bytes else { return }
            combined.append(bytes, count: count)
        }
        combined.append(hitchNewLine)
    }
    
    public var description: Hitch {
        let combined = Hitch()
        process(hitch: combined,
                socket: nil,
                userSession: nil)
        return combined
    }
    
    func process(hitch: Hitch?,
                 socket: SocketSendable?,
                 userSession: UserSession?) {
        // Multifunctional method. Can be to put the data directly to a socket, or can be used
        // to bake it to a hitch.  Or both.
        
        // We're greedy and optimize for non-statis http responses
        let combined: Hitch = hitch ?? Hitch(capacity: 512)
        combined.reserveCapacity(512)

        combined.append(status.hitch)
        combined.append(hitchNewLine)

        if cacheMaxAge > 0 {
            combined.append(hitchCacheControl)
            combined.append(number: cacheMaxAge)
            combined.append(hitchNewLine)
        }
        if let userSession = userSession {
            
            combined.append(hitchSetCookie1)
            combined.append(Picaroon.userSessionCookie)
            combined.append(.equal)
            combined.append(userSession.unsafeCookieSessionUUID)
            combined.append(hitchSetCookie2)
            
            for header in userSession.unsafeSessionHeaders {
                combined.append(header)
                combined.append(hitchNewLine)
            }
        }
        if let encoding = encoding {
            combined.append(hitchContentEncoding)
            combined.append(encoding)
            combined.append(hitchNewLine)
        }

        if let headers = headers {
            for header in headers {
                combined.append(header)
                combined.append(hitchNewLine)
            }
        }
        
        combined.append(hitchLastModified)
        combined.append(lastModified)
        combined.append(hitchNewLine)

        combined.append(hitchKeepAlive)
        
        // Three possibilities:
        // 1. There is no payload content
        // 2. There is a single payload content ( return content normally )
        // 3. There are multiple payload contents ( return as multipart/form-data )
        if let multipart = multipart {
            var multipartCount = 0
            
            multipartCount += hitchMultipartBoundary.count
            for part in multipart {
                multipartCount += part.multipartCount()
                multipartCount += hitchMultipartBoundary.count
            }
            multipartCount += hitchMultipartBoundary.count
            
            let multipartCombined = Hitch(capacity: multipartCount)
            
            for part in multipart {
                multipartCombined.append(hitchMultipartBoundary)
                part.multipartAppend(multipartCombined)
            }
            multipartCombined.append(hitchMultipartBoundary)
            
            combined.append(hitchContentType)
            combined.append(HttpContentType.formData.hitch)
            combined.append(hitchNewLine)
            
            combined.append(hitchContentLength)
            combined.append(number: multipartCombined.count)
            combined.append(hitchNewLine)
            combined.append(hitchNewLine)
            
            socket?.send(hitch: combined)
            socket?.send(hitch: multipartCombined)
            hitch?.append(multipartCombined)
            
        } else if let payload = payload {
            combined.append(hitchContentType)
            combined.append(type.hitch)
            combined.append(hitchNewLine)
            
            combined.append(hitchContentLength)
            combined.append(number: payload.count)
            combined.append(hitchNewLine)
            combined.append(hitchNewLine)
            
            socket?.send(hitch: combined)
            payload.using { bytes, count in
                if let bytes = bytes {
                    socket?.send(bytes: bytes, count: count)
                    hitch?.append(bytes, count: count)
                }
            }
        } else {
            
            combined.append(hitchContentType)
            combined.append(HttpContentType.txt.rawValue)
            combined.append(hitchNewLine)
            
            combined.append(hitchContentLength)
            combined.append(.zero)
            combined.append(hitchNewLine)
            combined.append(hitchNewLine)
            
            combined.append(hitchNewLine)
            socket?.send(hitch: combined)
        }
    }
    
    func send(socket: SocketSendable,
              userSession: UserSession?) {
        process(hitch: nil,
                socket: socket,
                userSession: userSession)
    }
}
