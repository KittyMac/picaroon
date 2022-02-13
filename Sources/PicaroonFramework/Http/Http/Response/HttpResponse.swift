import Flynn
import Foundation
import Hitch
import Spanker

private let hitchContentDispositionFormDataWithNameFormat = "Content-Disposition:form-data;name=\"{0}\"\r\n".hitch()
private let hitchContentDiscpositionFormData = "Content-Disposition:form-data\r\n".hitch()
private let hitchContentLength = "Content-Length:{0}\r\n".hitch()
private let hitchNewLine = "\r\n".hitch()
private let hitchNewLineFormat = "{0}\r\n".hitch()
private let hitchCacheControlFormat = "Cache-Control:public, max-age={0}\r\n".hitch()
private let hitchSetCookieFormat = "Set-Cookie:{0}={1}; HttpOnly\r\n".hitch()
private let hitchContentEncodingFormat = "Content-Encoding: {0}\r\n".hitch()
private let hitchLastModifiedFormat = "Last-Modified:{0}\r\n".hitch()
private let hitchKeepAlive = "Connection:keep-alive\r\n".hitch()
private let hitchContentTypeFormat = "Content-Type:{0}\r\n".hitch()
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
    public static let sharedLastModifiedDateString = "\(sharedLastModifiedDate)".halfhitch()
    
    private let status: HttpStatus;
    private let type: HttpContentType
    private let headers: [Hitchable]?
    private let encoding: Hitchable?
    private let lastModified: Date
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
                lastModified: Date = sharedLastModifiedDate,
                cacheMaxAge: Int = 0) {
        self.status = .ok
        self.type = .txt
        self.headers = headers
        self.encoding = encoding
        self.lastModified = lastModified
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
                lastModified: Date = sharedLastModifiedDate,
                cacheMaxAge: Int = 0) {
        self.status = status
        self.type = type
        self.headers = headers
        self.encoding = encoding
        self.lastModified = lastModified
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
                lastModified: Date = sharedLastModifiedDate,
                cacheMaxAge: Int = 0) {
        self.status = status
        self.type = type
        self.headers = headers
        self.encoding = encoding
        self.lastModified = lastModified
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
                lastModified: Date = sharedLastModifiedDate,
                cacheMaxAge: Int = 0) {
        self.status = status
        self.type = type
        self.headers = headers
        self.encoding = encoding
        self.lastModified = lastModified
        self.cacheMaxAge = cacheMaxAge
        self.payload = payload
        self.multipart = nil
        self.multipartName = multipartName
        
        postInit()
    }
    
    @inlinable @inline(__always)
    func isNew(_ request: HttpRequest) -> Bool {
        if let modifiedDate = request.ifModifiedSince {
            return HttpResponse.sharedLastModifiedDateString != modifiedDate
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
            combined.append(format: hitchContentDispositionFormDataWithNameFormat, multipartName)
        } else {
            combined.append(hitchContentDiscpositionFormData)
        }
        combined.append(format: hitchContentLength, payload.count)
        combined.append(hitchNewLine)
        payload.using { bytes, count in
            guard let bytes = bytes else { return }
            combined.append(bytes, count: count)
        }
        combined.append(hitchNewLine)
    }
    
    func process(hitch: Hitch?,
                 socket: SocketSendable?,
                 userSession: UserSession?) {
        // Multifunctional method. Can be to put the data directly to a socket, or can be used
        // to bake it to a hitch.  Or both.
        
        var multipartCount = 0
        
        var capacity = 512
        if let payload = payload {
            capacity += payload.count
        }
        if let multipart = multipart {
            multipartCount += hitchMultipartBoundary.count
            for part in multipart {
                multipartCount += part.multipartCount()
                multipartCount += hitchMultipartBoundary.count
            }
            multipartCount += hitchMultipartBoundary.count
            
            capacity += multipartCount
        }
        
        let combined: Hitch = hitch ?? Hitch()
        
        combined.reserveCapacity(capacity)

        combined.append(status.string)
        combined.append(hitchNewLine)

        if cacheMaxAge > 0 {
            combined.append(format: hitchCacheControlFormat, cacheMaxAge)
        }
        if let userSession = userSession {
            combined.append(format: hitchSetCookieFormat, Picaroon.userSessionCookie, userSession.unsafeSessionUUID.prefix(36))
            for header in userSession.unsafeSessionHeaders {
                combined.append(format: hitchNewLineFormat, header)
            }
        }
        if let encoding = encoding {
            combined.append(format: hitchContentEncodingFormat, encoding)
        }

        if let headers = headers {
            for header in headers {
                combined.append(format: hitchNewLineFormat, header)
            }
        }
        
        combined.append(format: hitchLastModifiedFormat, lastModified)
        combined.append(hitchKeepAlive)
        
        // Three possibilities:
        // 1. There is no payload content
        // 2. There is a single payload content ( return content normally )
        // 3. There are multiple payload contents ( return as multipart/form-data )
        if let multipart = multipart {
            let multipartCombined = Hitch(capacity: multipartCount)
            
            for part in multipart {
                multipartCombined.append(hitchMultipartBoundary)
                part.multipartAppend(multipartCombined)
            }
            multipartCombined.append(hitchMultipartBoundary)
            
            combined.append(format: hitchContentTypeFormat, HttpContentType.formData.string)
            combined.append(format: hitchContentLength, multipartCombined.count)
            combined.append(hitchNewLine)
            
            socket?.send(hitch: combined)
            socket?.send(hitch: multipartCombined)
            hitch?.append(multipartCombined)
            
        } else if let payload = payload {
            // There is no payload, we're done!
            combined.append(format: hitchContentTypeFormat, type.string)
            combined.append(format: hitchContentLength, payload.count)
            combined.append(hitchNewLine)
            
            socket?.send(hitch: combined)
            payload.using { bytes, count in
                if let bytes = bytes {
                    socket?.send(bytes: bytes, count: count)
                    hitch?.append(bytes, count: count)
                }
            }
        } else {
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
