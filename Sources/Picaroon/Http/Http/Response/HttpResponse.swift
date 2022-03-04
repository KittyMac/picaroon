import Flynn
import Foundation
import Hitch
import Spanker

private let hitchContentLength: Hitch = "Content-Length:"
private let hitchNewLine: Hitch = "\r\n"
private let hitchCacheControl: Hitch = "Cache-Control:public, max-age="

private let hitchSetCookie1: Hitch = "Set-Cookie:"
private let hitchSetCookie2: Hitch = "; HttpOnly\r\n"

private let hitchSessionId1: Hitch = "Session-Id:"

private let hitchContentEncoding: Hitch = "Content-Encoding:"
private let hitchLastModified: Hitch = "Last-Modified:"
private let hitchKeepAlive: Hitch = "Connection:keep-alive\r\n"
private let hitchContentType: Hitch = "Content-Type:"

protocol SocketSendable {
    @discardableResult func send(hitch: Hitch) -> Int
    @discardableResult func send(data: Data) -> Int
    @discardableResult func send(bytes: UnsafePointer<UInt8>?,
                                 count: Int) -> Int
}

extension Socket: SocketSendable {
    
}

fileprivate func detectEncoding(payload: Payloadable?) -> HalfHitch? {
    // Check for magic bytes which will let us know if this is compressed content or not
    var encoding: HalfHitch? = nil
    payload?.using { bytes, count in
        guard let bytes = bytes else { return }
        guard count > 10 else { return }
        // gzip magic header: https://en.wikipedia.org/wiki/Gzip
        if bytes[0] == 0x1F && bytes[1] == 0x8B && bytes[2] == 0x08 {
            encoding = "gzip"
        }
    }
    return encoding
}

/// Holds all of the information necessary to write an http response to a socket. Does not
/// copy the data it is given.
public class HttpResponse {
    
    public static let sharedLastModifiedDate = Date()
    public static let sharedLastModifiedDateHitch = Hitch(string: "\(sharedLastModifiedDate)")
    public static let sharedLastModifiedDateHalfHitch = sharedLastModifiedDateHitch.halfhitch()
    
    private let status: HttpStatus;
    private let type: HttpContentType
    private let headers: [HalfHitch]?
    private let encoding: HalfHitch?
    private let lastModified: Hitch
    private let cacheMaxAge: Int
    
    private let payload: Payloadable?

    func postInit() {

    }
        
    public init(httpResponse: HttpResponse,
                headers: [HalfHitch]? = nil,
                encoding: HalfHitch? = nil,
                lastModified: Date? = nil,
                cacheMaxAge: Int? = nil) {
        self.status = httpResponse.status
        self.type = httpResponse.type
        self.headers = headers ?? httpResponse.headers
        self.encoding = encoding ?? httpResponse.encoding
        if let lastModified = lastModified {
            self.lastModified = Hitch(string: lastModified.description)
        } else {
            self.lastModified = httpResponse.lastModified
        }
        self.cacheMaxAge = cacheMaxAge ?? httpResponse.cacheMaxAge
        self.payload = httpResponse.payload
        
        postInit()
    }
        
    public init(status: HttpStatus,
                type: HttpContentType,
                headers: [HalfHitch]? = nil,
                encoding: HalfHitch? = nil,
                lastModified: Date? = nil,
                cacheMaxAge: Int = 0) {
        self.status = status
        self.type = type
        self.headers = headers
        self.encoding = encoding
        if let lastModified = lastModified {
            self.lastModified = Hitch(string: lastModified.description)
        } else {
            self.lastModified = HttpResponse.sharedLastModifiedDateHitch
        }
        self.cacheMaxAge = cacheMaxAge
        self.payload = nil
        
        postInit()
    }
    
    public init(status: HttpStatus,
                type: HttpContentType,
                payload: Payloadable,
                headers: [HalfHitch]? = nil,
                encoding: HalfHitch? = nil,
                lastModified: Date? = nil,
                cacheMaxAge: Int = 0) {
        self.status = status
        self.type = type
        self.headers = headers
        self.encoding = encoding ?? detectEncoding(payload: payload)
        if let lastModified = lastModified {
            self.lastModified = Hitch(string: lastModified.description)
        } else {
            self.lastModified = HttpResponse.sharedLastModifiedDateHitch
        }
        self.cacheMaxAge = cacheMaxAge
        self.payload = payload
        
        postInit()
    }
    
    @inlinable @inline(__always)
    func isNew(_ request: HttpRequest) -> Bool {
        if let modifiedDate = request.ifModifiedSince {
            return HttpResponse.sharedLastModifiedDateHalfHitch != modifiedDate
        }
        return true
    }
        
    public var description: Hitch {
        let combined = Hitch()
        process(config: nil,
                hitch: combined,
                socket: nil,
                userSession: nil)
        return combined
    }
    
    func process(config: ServerConfig?,
                 hitch: Hitch?,
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
            
            if config?.sessionPer == .api {
                combined.append(hitchSessionId1)
                combined.append(userSession.unsafeJavascriptSessionUUID)
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
        
        if let payload = payload {
            payload.using { bytes, count in
                
                combined.append(hitchContentType)
                combined.append(type.hitch)
                combined.append(hitchNewLine)
                
                combined.append(hitchContentLength)
                combined.append(number: count)
                combined.append(hitchNewLine)
                combined.append(hitchNewLine)
                socket?.send(hitch: combined)
                
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
    
    func send(config: ServerConfig,
              socket: SocketSendable,
              userSession: UserSession?) {
        process(config: config,
                hitch: nil,
                socket: socket,
                userSession: userSession)
    }
}
