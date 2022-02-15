import Flynn
import Foundation
import Hitch
import Spanker

private let hitchContentLength: Hitch = "Content-Length:"
private let hitchNewLine: Hitch = "\r\n"
private let hitchCacheControl: Hitch = "Cache-Control:public, max-age="

private let hitchSetCookie1: Hitch = "Set-Cookie:"
private let hitchSetCookie2: Hitch = "; HttpOnly\r\n"

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
    private let services: [HttpResponse]?
    private let serviceName: Hitch?

    func postInit() {

    }
        
    public init(httpResponse: HttpResponse,
                name: Hitch) {
        self.status = httpResponse.status
        self.type = httpResponse.type
        self.headers = httpResponse.headers
        self.encoding = httpResponse.encoding
        self.lastModified = httpResponse.lastModified
        self.cacheMaxAge = httpResponse.cacheMaxAge
        self.payload = httpResponse.payload
        self.services = httpResponse.services
        self.serviceName = name
        
        postInit()
    }
        
    public init(status: HttpStatus,
                type: HttpContentType,
                name: Hitch? = nil,
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
        self.services = nil
        self.serviceName = name
        
        postInit()
    }
    
    public init(services: [HttpResponse],
                name: Hitch? = nil,
                headers: [HalfHitch]? = nil,
                encoding: HalfHitch? = nil,
                lastModified: Date? = nil,
                cacheMaxAge: Int = 0) {
        self.status = .ok
        self.type = .txt
        self.headers = headers
        self.encoding = encoding
        if let lastModified = lastModified {
            self.lastModified = Hitch(string: lastModified.description)
        } else {
            self.lastModified = HttpResponse.sharedLastModifiedDateHitch
        }
        self.cacheMaxAge = cacheMaxAge
        self.payload = nil
        self.services = services
        self.serviceName = name
        
        postInit()
    }

    
    public init(status: HttpStatus,
                type: HttpContentType,
                payload: ConvertableToPayloadable,
                name: Hitch? = nil,
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
        self.payload = payload.payload
        self.services = nil
        self.serviceName = name
        
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
        
        
        var reifiedPayload = payload
        
        if let services = services {
            // Since multipart http responses are not capable enough for what I want to do, we have to support
            // multiple http responses in a but uniquely.  Here's how it goes:
            // 1. Json reponses are stored in http headers, using the service name as the header name "userservice: [1,2,3,4,5]"
            // 2. If a non-json response exists, it will become the main content of the http response
            // 3. If no non-json response exists, then main content will be empty
            // 4. If multiple json responses exist, then the main content will be internal server error
            // 5. Headers attached to sub responses becaome the service name "dot" subheader "userservice.location: main"
            //
            // This system allows us to reach our main goal of being able to serve pre-gzipped resources alongside
            // json results from service calls
            
            // Identify the main content service response, fail if there is more than one
            var contentResponse: HttpResponse?
            for service in services where service.type != .json {
                guard contentResponse == nil else {
                    combined.clear()
                    HttpStaticResponse.internalServerError.process(hitch: hitch,
                                                                   socket: socket,
                                                                   userSession: userSession)
                    return
                }
                contentResponse = service
            }

            // Handle injecting everything into the headers
            for service in services {
                guard let serviceName = service.serviceName else { continue }
                
                if service.type == .json {
                    combined.append(serviceName)
                    combined.append(.colon)
                    service.payload?.using { bytes, count in
                        if let bytes = bytes {
                            combined.append(bytes, count: count)
                        }
                    }
                    combined.append(hitchNewLine)
                }
                
                if let serviceHeaders = service.headers {
                    for serviceHeader in serviceHeaders {
                        combined.append(serviceName)
                        combined.append(.dot)
                        combined.append(serviceHeader)
                        combined.append(.colon)
                        service.payload?.using { bytes, count in
                            if let bytes = bytes {
                                combined.append(bytes, count: count)
                            }
                        }
                        combined.append(hitchNewLine)
                    }
                }
            }
            
            reifiedPayload = contentResponse?.payload
        }
        
        
        
        if let reifiedPayload = reifiedPayload {
            combined.append(hitchContentType)
            combined.append(type.hitch)
            combined.append(hitchNewLine)
            
            combined.append(hitchContentLength)
            combined.append(number: reifiedPayload.count)
            combined.append(hitchNewLine)
            combined.append(hitchNewLine)
            
            socket?.send(hitch: combined)
            reifiedPayload.using { bytes, count in
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
