import Flynn
import Foundation
import Hitch
import Spanker


// swiftlint:disable function_body_length
// swiftlint:disable cyclomatic_complexity
// swiftlint:disable identifier_name
// swiftlint:disable type_body_length
// swiftlint:disable file_length

public class HttpRequest {
    
    public var method: HttpMethod = .UNKNOWN
    
    public var url: HalfHitch?
    public var urlParameters: HalfHitch?
    public var host: HalfHitch?
    public var userAgent: HalfHitch?
    public var authorization: HalfHitch?
    public var accept: HalfHitch?
    public var acceptEncoding: HalfHitch?
    public var acceptCharset: HalfHitch?
    public var acceptLanguage: HalfHitch?
    public var connection: HalfHitch?
    public var upgradeInsecureRequests: HalfHitch?
    public var contentLength: HalfHitch?
    public var contentType: HalfHitch?
    public var contentDisposition: HalfHitch?
    public var ifModifiedSince: HalfHitch?
    public var ifNoneMatch: HalfHitch?
    public var cookie: HalfHitch?
    public var expect: HalfHitch?
    public var flynnTag: HalfHitch?
    public var sessionId: HalfHitch?
    public var sid: HalfHitch?
    public var xForwardedFor: HalfHitch?
    public var deviceId: HalfHitch?
    public var waitingCount: HalfHitch?
    public var activeCount: HalfHitch?
    public var maxConcurrent: HalfHitch?
    
    public var content: HalfHitch?
    public var json: JsonElement?
    
    public var description: Hitch?
    
    public var cookies: [Hitch: Hitch] {
        var _cookies: [Hitch: Hitch] = [:]
        
        if let cookie = cookie {
            // cookie1=something; cookie2=another
            let keyValuePairs: [Hitch] = cookie.components(separatedBy: ";")
            for pair in keyValuePairs {
                let parts: [Hitch] = pair.trim().components(separatedBy: "=")
                if parts.count == 2 {
                    _cookies[parts[0]] = parts[1]
                }
            }
        }
        return _cookies
    }
    
    private var parameters: [String: String]?
    public func parameter(name: String) -> String? {
        if let parameters = parameters {
            return parameters[name]
        }

        guard let urlParameters = urlParameters else { return nil }
        guard let url = URL(string: "https://www.a.com/b?\(urlParameters)") else { return nil }

        parameters = [:]

        if let components = URLComponents(url: url,
                                          resolvingAgainstBaseURL: false),
           let items = components.queryItems {
            for item in items {
                parameters?[item.name] = item.value
            }
            return parameters?[name]
        }
        return nil
    }
    
    public init?(config: ServerConfig,
                 request buffer: UnsafePointer<UInt8>,
                 size bufferSize: Int) {
        guard bufferSize > 6 else { return nil }
                
        let startPtr = buffer
        let endPtr = buffer + bufferSize
        var ptr = startPtr
        var size = ptr - startPtr
        var current: UInt8 = 0
        
        // Handle the first line
        current = ptr[0]
                                
        if current == .G &&
            ptr[1] == .E &&
            ptr[2] == .T &&
            ptr[3] == .space {
            ptr += 3
            method = .GET
        } else
        if current == .H &&
            ptr[1] == .E &&
            ptr[2] == .A &&
            ptr[3] == .D &&
            ptr[4] == .space {
            ptr += 4
            method = .HEAD
        } else
        if current == .P &&
            ptr[1] == .U &&
            ptr[2] == .T &&
            ptr[3] == .space {
            ptr += 3
            method = .PUT
        } else
        if current == .P &&
            ptr[1] == .O &&
            ptr[2] == .S &&
            ptr[3] == .T &&
            ptr[4] == .space {
            ptr += 4
            method = .POST
        } else
        if current == .D &&
            ptr[1] == .E &&
            ptr[2] == .L &&
            ptr[3] == .E &&
            ptr[4] == .T &&
            ptr[5] == .E &&
            ptr[6] == .space {
            ptr += 6
            method = .DELETE
        } else {
            return nil
        }
        
        // We identified the method, now parse the rest of the line
        let defaultPtr = ptr + 1
        
        var urlParametersStartPtr = defaultPtr
        var urlParametersEndPtr = defaultPtr
        var sessionStartPtr = defaultPtr
        var sessionEndPtr = defaultPtr
        let urlStartPtr = defaultPtr
        var urlEndPtr = defaultPtr
        
        ptr += 1
        
        while ptr < endPtr {
            size = ptr - startPtr
            current = ptr[0]
            
            if urlParametersStartPtr == defaultPtr &&
                ptr[-1] == .questionMark {
                urlParametersStartPtr = ptr
            }
            
            if size >= 4 &&
                ptr[-4] == .s &&
                ptr[-3] == .i &&
                ptr[-2] == .d &&
                ptr[-1] == .equal {
                sessionStartPtr = ptr
            }
            
            if size >= 6 &&
                ptr[-6] == .s &&
                ptr[-5] == .i &&
                ptr[-4] == .d &&
                ptr[-3] == .percentSign &&
                ptr[-2] == .three &&
                (ptr[-1] == .D || ptr[-1] == .d) {
                sessionStartPtr = ptr
            }
            
            if current == .ampersand &&
                sessionStartPtr != defaultPtr {
                sessionEndPtr = ptr
            }
            
            if current == .carriageReturn ||
                current == .newLine ||
                current == .space {
                
                if sessionStartPtr != defaultPtr &&
                    sessionEndPtr == defaultPtr {
                    sessionEndPtr = ptr
                }
                if urlParametersStartPtr != defaultPtr {
                    urlParametersEndPtr = ptr
                    urlEndPtr = urlParametersStartPtr - 1
                } else {
                    urlEndPtr = ptr
                }
                break
            }
            
            ptr += 1
        }
                
        url = HalfHitch(sourceObject: nil,
                        raw: buffer,
                        count: bufferSize,
                        from: urlStartPtr - buffer,
                        to: urlEndPtr - buffer)
        
        if sessionStartPtr < sessionEndPtr {
            sid = HalfHitch(sourceObject: nil,
                            raw: buffer,
                            count: bufferSize,
                            from: sessionStartPtr - buffer,
                            to: sessionEndPtr - buffer)
        }
        if urlParametersStartPtr < urlParametersEndPtr {
            urlParameters = HalfHitch(sourceObject: nil,
                                      raw: buffer,
                                      count: bufferSize,
                                      from: urlParametersStartPtr - buffer,
                                      to: urlParametersEndPtr - buffer)
        }
        
        // Advance to the end of the line
        while ptr < endPtr {
            if ptr[-1] == .carriageReturn && ptr[0] == .newLine {
                ptr += 1
                break
            }
            ptr += 1
        }
        
        // Every line after the first line
        while ptr < endPtr {
            size = ptr - startPtr
            current = ptr[0]
            
            // Every line after the header is a Key-Word-No-Space: Whatever Until New Line
            // 1. advance until we find the ":", or a whitespace
            var keyEnd = ptr + 1
            while ptr < endPtr {
                
                if current == .carriageReturn || current == .newLine {
                    while ptr < endPtr && (current == .carriageReturn || current == .newLine) {
                        ptr += 1
                        current = ptr[0]
                    }
                    // If we reach here, we're at the point we're looking for payload data
                    if let contentLength = contentLength,
                       let contentLengthBytes = contentLength.toInt() {
                        guard endPtr - ptr >= contentLengthBytes else {
                            return nil
                        }
                        content = HalfHitch(sourceObject: nil,
                                            raw: buffer,
                                            count: bufferSize,
                                            from: ptr - buffer,
                                            to: (ptr - buffer) + contentLengthBytes)
                    }
                    
                    // Congrats! we have successfully parsed the http request. We now need to bake the request
                    // (ie copy to our own buffer before we pass it along to other people)
                    bake(buffer: buffer,
                         bufferSize: bufferSize)
                    
                    return
                } else if current == .colon {
                    keyEnd = ptr
                    ptr += 1
                    current = ptr[0]
                    break
                }
                ptr += 1
                current = ptr[0]
            }
            
            // 2. Skip whitespace
            while ptr < endPtr && (current == .space || current == .tab) {
                ptr += 1
                current = ptr[0]
            }
            
            let valueStart = ptr
            
            // 3. Advance to the end of the line
            while ptr < endPtr && current != .carriageReturn && current != .newLine {
                ptr += 1
                current = ptr[0]
            }
            
            // 3. For speed, we only match against the keys we support (no generics)
            parseKeyValue(buffer: buffer,
                          bufferSize: bufferSize,
                          ptr: ptr,
                          valueStart: valueStart,
                          keyEnd: keyEnd)
            
            // Advance to the next line
            if ptr[0] == .carriageReturn {
                ptr += 1
                if ptr[0] == .newLine {
                    ptr += 1
                }
            } else if ptr[0] == .newLine {
                ptr += 1
            } else {
                ptr += 1
            }
        }
        
        return nil
    }
    
    public init?(multipart buffer: UnsafePointer<UInt8>,
                 size bufferSize: Int) {
        
        let startPtr = buffer
        let endPtr = buffer + bufferSize
        
        var ptr = startPtr + 3
        
        var lineNumber = 0
        
        while ptr < endPtr {
            // Every line after the header is a Key-Word-No-Space: Whatever Until New Line
            // 1. advance until we find the ":", or a whitespace
            var keyEnd = ptr + 1
            while ptr < endPtr {
                if ptr[0] == .carriageReturn || ptr[0] == .newLine {
                    while ptr < endPtr && ( ptr[0] == .carriageReturn ||
                                                ptr[0] == .newLine) {
                        ptr += 1
                    }
                    
                    // If we reach here, the rest of the content is the payload
                    if endPtr - ptr >= 0 {
                        content = HalfHitch(sourceObject: nil,
                                            raw: buffer,
                                            count: bufferSize,
                                            from: ptr - buffer,
                                            to: (ptr - buffer) + (endPtr - ptr))
                    }
                    return
                }
                if ptr[0] == .colon {
                    keyEnd = ptr
                    ptr += 1
                    break
                }
                ptr += 1
            }
            
            // 2. Skip whitespace
            while ptr < endPtr && (ptr[0] == .space || ptr[0] == .tab) {
                ptr += 1
            }
            
            let valueStart = ptr
            
            // 3. Advance to the end of the line
            while ptr < endPtr && ptr[0] != .carriageReturn && ptr[0] != .newLine {
                ptr += 1
            }
            
            // 3. For speed, we only match against the keys we support (no generics)
            parseKeyValue(buffer: buffer,
                          bufferSize: bufferSize,
                          ptr: ptr,
                          valueStart: valueStart,
                          keyEnd: keyEnd)
            
            // Advance to the next line
            if ptr[0] == .carriageReturn {
                ptr += 1
                if ptr[0] == .newLine {
                    ptr += 1
                }
            } else if ptr[0] == .newLine {
                ptr += 1
            }
            
            if ptr[0] == .newLine {
                lineNumber += 1
            }
            
            ptr += 1
        }
        
        return nil
    }
    
    @inlinable
    func bake(buffer: UnsafePointer<UInt8>,
              bufferSize: Int,
              using: HalfHitch?) -> HalfHitch? {
        guard let halfhitch = using else { return nil }
        guard let oldRaw = halfhitch.raw() else { return nil }
        guard let description = description else { return nil }
        guard let newRaw = description.raw() else { return nil }
        
        let startIndex = oldRaw - buffer
        
        return HalfHitch(sourceObject: description,
                         raw: newRaw,
                         count: bufferSize,
                         from: startIndex,
                         to: startIndex + halfhitch.count)
    }
    
    @inlinable
    func bake(buffer: UnsafePointer<UInt8>,
              bufferSize: Int) {
        
        description = Hitch(bytes: buffer, offset: 0, count: bufferSize)
        
        url = bake(buffer: buffer, bufferSize: bufferSize, using: url)
        urlParameters = bake(buffer: buffer, bufferSize: bufferSize, using: urlParameters)
        host = bake(buffer: buffer, bufferSize: bufferSize, using: host)
        userAgent = bake(buffer: buffer, bufferSize: bufferSize, using: userAgent)
        authorization = bake(buffer: buffer, bufferSize: bufferSize, using: authorization)
        accept = bake(buffer: buffer, bufferSize: bufferSize, using: accept)
        acceptEncoding = bake(buffer: buffer, bufferSize: bufferSize, using: acceptEncoding)
        acceptCharset = bake(buffer: buffer, bufferSize: bufferSize, using: acceptCharset)
        acceptLanguage = bake(buffer: buffer, bufferSize: bufferSize, using: acceptLanguage)
        connection = bake(buffer: buffer, bufferSize: bufferSize, using: connection)
        upgradeInsecureRequests = bake(buffer: buffer, bufferSize: bufferSize, using: upgradeInsecureRequests)
        contentLength = bake(buffer: buffer, bufferSize: bufferSize, using: contentLength)
        contentType = bake(buffer: buffer, bufferSize: bufferSize, using: contentType)
        contentDisposition = bake(buffer: buffer, bufferSize: bufferSize, using: contentDisposition)
        ifModifiedSince = bake(buffer: buffer, bufferSize: bufferSize, using: ifModifiedSince)
        ifNoneMatch = bake(buffer: buffer, bufferSize: bufferSize, using: ifNoneMatch)
        cookie = bake(buffer: buffer, bufferSize: bufferSize, using: cookie)
        expect = bake(buffer: buffer, bufferSize: bufferSize, using: expect)
        flynnTag = bake(buffer: buffer, bufferSize: bufferSize, using: flynnTag)
        sessionId = bake(buffer: buffer, bufferSize: bufferSize, using: sessionId)
        sid = bake(buffer: buffer, bufferSize: bufferSize, using: sid)
        xForwardedFor = bake(buffer: buffer, bufferSize: bufferSize, using: xForwardedFor)
        deviceId = bake(buffer: buffer, bufferSize: bufferSize, using: deviceId)
        waitingCount = bake(buffer: buffer, bufferSize: bufferSize, using: waitingCount)
        activeCount = bake(buffer: buffer, bufferSize: bufferSize, using: activeCount)
        maxConcurrent = bake(buffer: buffer, bufferSize: bufferSize, using: maxConcurrent)
        content = bake(buffer: buffer, bufferSize: bufferSize, using: content)
        
        // If we have json content, automatically parse it out
        if let content = content {
            json = Spanker.parse(halfhitch: content)
        }
    }
    
    @inlinable
    func parseKeyValue(buffer: UnsafePointer<UInt8>,
                       bufferSize: Int,
                       ptr: UnsafePointer<UInt8>,
                       valueStart: UnsafePointer<UInt8>,
                       keyEnd: UnsafePointer<UInt8>) {
        let size = keyEnd - buffer
        
        if host == nil,
            size >= 5,
            keyEnd[-4] == .H || keyEnd[-4] == .h,
            //keyEnd[-3] == .o,
            keyEnd[-2] == .s,
            keyEnd[-1] == .t {
            host = HalfHitch(sourceObject: nil,
                             raw: buffer,
                             count: bufferSize,
                             from: valueStart - buffer,
                             to: ptr - buffer)
        }
        
        if userAgent == nil,
            size >= 10,
            keyEnd[-10] == .u || keyEnd[-10] == .U,
            //keyEnd[-9] == .s || keyEnd[-9] == .S,
            keyEnd[-8] == .e || keyEnd[-8] == .E,
            //keyEnd[-7] == .r || keyEnd[-7] == .R,
            keyEnd[-6] == .minus,
            //keyEnd[-5] == .a || keyEnd[-5] == .A,
            keyEnd[-4] == .g || keyEnd[-4] == .G,
            //keyEnd[-3] == .e || keyEnd[-3] == .E,
            keyEnd[-2] == .n || keyEnd[-2] == .N,
            keyEnd[-1] == .t || keyEnd[-1] == .T {
            userAgent = HalfHitch(sourceObject: nil,
                                  raw: buffer,
                                  count: bufferSize,
                                  from: valueStart - buffer,
                                  to: ptr - buffer)
        }
        
        if authorization == nil,
            size >= 13,
            keyEnd[-13] == .a || keyEnd[-13] == .A,
            //keyEnd[-12] == .u || keyEnd[-12] == .U,
            keyEnd[-11] == .t || keyEnd[-11] == .T,
            //keyEnd[-10] == .h || keyEnd[-10] == .H,
            keyEnd[-9] == .o || keyEnd[-9] == .O,
            //keyEnd[-8] == .r || keyEnd[-8] == .R,
            keyEnd[-7] == .i || keyEnd[-7] == .I,
            //keyEnd[-6] == .z || keyEnd[-6] == .Z,
            keyEnd[-5] == .a || keyEnd[-5] == .A,
            //keyEnd[-4] == .t || keyEnd[-4] == .T,
            keyEnd[-3] == .i || keyEnd[-3] == .I,
            //keyEnd[-2] == .o || keyEnd[-2] == .O,
            keyEnd[-1] == .n || keyEnd[-1] == .N {
            authorization = HalfHitch(sourceObject: nil,
                                      raw: buffer,
                                      count: bufferSize,
                                      from: valueStart - buffer,
                                      to: ptr - buffer)
        }
        
        if accept == nil,
            size >= 6,
            keyEnd[-6] == .a || keyEnd[-6] == .A,
            //keyEnd[-5] == .c || keyEnd[-5] == .C,
            keyEnd[-4] == .c || keyEnd[-4] == .C,
            //keyEnd[-3] == .e || keyEnd[-3] == .E,
            keyEnd[-2] == .p || keyEnd[-2] == .P,
            keyEnd[-1] == .t || keyEnd[-1] == .T {
            accept = HalfHitch(sourceObject: nil,
                               raw: buffer,
                               count: bufferSize,
                               from: valueStart - buffer,
                               to: ptr - buffer)
        }
        
        if acceptEncoding == nil,
            size >= 15,
            keyEnd[-15] == .a || keyEnd[-15] == .A,
            //keyEnd[-14] == .c || keyEnd[-14] == .C,
            keyEnd[-13] == .c || keyEnd[-13] == .C,
            //keyEnd[-12] == .e || keyEnd[-12] == .E,
            keyEnd[-11] == .p || keyEnd[-11] == .P,
            //keyEnd[-10] == .t || keyEnd[-10] == .T,
            keyEnd[-9] == .minus,
            //keyEnd[-8] == .e || keyEnd[-8] == .E,
            keyEnd[-7] == .n || keyEnd[-7] == .N,
            //keyEnd[-6] == .c || keyEnd[-6] == .C,
            keyEnd[-5] == .o || keyEnd[-5] == .O,
            //keyEnd[-4] == .d || keyEnd[-4] == .D,
            keyEnd[-3] == .i || keyEnd[-3] == .I,
            //keyEnd[-2] == .n || keyEnd[-2] == .N,
            keyEnd[-1] == .g || keyEnd[-1] == .G {
            acceptEncoding = HalfHitch(sourceObject: nil,
                                       raw: buffer,
                                       count: bufferSize,
                                       from: valueStart - buffer,
                                       to: ptr - buffer)
        }
        
        if acceptCharset == nil,
            size >= 14,
            keyEnd[-14] == .a || keyEnd[-14] == .A,
            //keyEnd[-13] == .c || keyEnd[-13] == .C,
            keyEnd[-12] == .c || keyEnd[-12] == .C,
            //keyEnd[-11] == .e || keyEnd[-11] == .E,
            keyEnd[-10] == .p || keyEnd[-10] == .P,
            //keyEnd[-9] == .t || keyEnd[-9] == .T,
            keyEnd[-8] == .minus,
            //keyEnd[-7] == .c || keyEnd[-7] == .C,
            keyEnd[-6] == .h || keyEnd[-6] == .H,
            //keyEnd[-5] == .a || keyEnd[-5] == .A,
            keyEnd[-4] == .r || keyEnd[-4] == .R,
            //keyEnd[-3] == .s || keyEnd[-3] == .S,
            keyEnd[-2] == .e || keyEnd[-2] == .E,
            keyEnd[-1] == .t || keyEnd[-1] == .T {
            acceptCharset = HalfHitch(sourceObject: nil,
                                      raw: buffer,
                                      count: bufferSize,
                                      from: valueStart - buffer,
                                      to: ptr - buffer)
        }
        
        if acceptLanguage == nil,
            size >= 15,
            keyEnd[-15] == .a || keyEnd[-15] == .A,
            //keyEnd[-14] == .c || keyEnd[-14] == .C,
            keyEnd[-13] == .c || keyEnd[-13] == .C,
            //keyEnd[-12] == .e || keyEnd[-12] == .E,
            keyEnd[-11] == .p || keyEnd[-11] == .P,
            //keyEnd[-10] == .t || keyEnd[-10] == .T,
            keyEnd[-9] == .minus,
            //keyEnd[-8] == .l || keyEnd[-8] == .L,
            keyEnd[-7] == .a || keyEnd[-7] == .A,
            //keyEnd[-6] == .n || keyEnd[-6] == .N,
            keyEnd[-5] == .g || keyEnd[-5] == .G,
            //keyEnd[-4] == .u || keyEnd[-4] == .U,
            keyEnd[-3] == .a || keyEnd[-3] == .A,
            //keyEnd[-2] == .g || keyEnd[-2] == .G,
            keyEnd[-1] == .e || keyEnd[-1] == .E {
            acceptLanguage = HalfHitch(sourceObject: nil,
                                       raw: buffer,
                                       count: bufferSize,
                                       from: valueStart - buffer,
                                       to: ptr - buffer)
        }
        
        if connection == nil,
            size >= 10,
            keyEnd[-10] == .c || keyEnd[-10] == .C,
            //keyEnd[-9] == .o || keyEnd[-9] == .O,
            keyEnd[-8] == .n || keyEnd[-8] == .N,
            //keyEnd[-7] == .n || keyEnd[-7] == .N,
            keyEnd[-6] == .e || keyEnd[-6] == .E,
            //keyEnd[-5] == .c || keyEnd[-5] == .C,
            keyEnd[-4] == .t || keyEnd[-4] == .T,
            //keyEnd[-3] == .i || keyEnd[-3] == .I,
            keyEnd[-2] == .o || keyEnd[-2] == .O,
            keyEnd[-1] == .n || keyEnd[-1] == .N {
            connection = HalfHitch(sourceObject: nil,
                                   raw: buffer,
                                   count: bufferSize,
                                   from: valueStart - buffer,
                                   to: ptr - buffer)
        }
        
        if upgradeInsecureRequests == nil,
            size >= 25,
            keyEnd[-25] == .u || keyEnd[-25] == .U,
            //keyEnd[-24] == .p || keyEnd[-24] == .P,
            keyEnd[-23] == .g || keyEnd[-23] == .G,
            //keyEnd[-22] == .r || keyEnd[-22] == .R,
            keyEnd[-21] == .a || keyEnd[-21] == .A,
            //keyEnd[-20] == .d || keyEnd[-20] == .D,
            keyEnd[-19] == .e || keyEnd[-19] == .E,
            //keyEnd[-18] == .minus,
            keyEnd[-17] == .i || keyEnd[-17] == .I,
            //keyEnd[-16] == .n || keyEnd[-16] == .N,
            keyEnd[-15] == .s || keyEnd[-15] == .S,
            //keyEnd[-14] == .e || keyEnd[-14] == .E,
            keyEnd[-13] == .c || keyEnd[-13] == .C,
            //keyEnd[-12] == .u || keyEnd[-12] == .U,
            keyEnd[-11] == .r || keyEnd[-11] == .R,
            //keyEnd[-10] == .e || keyEnd[-10] == .E,
            keyEnd[-9] == .minus,
            //keyEnd[-8] == .r || keyEnd[-8] == .R,
            keyEnd[-7] == .e || keyEnd[-7] == .E,
            //keyEnd[-6] == .q || keyEnd[-6] == .Q,
            keyEnd[-5] == .u || keyEnd[-5] == .U,
            //keyEnd[-4] == .e || keyEnd[-4] == .E,
            keyEnd[-3] == .s || keyEnd[-3] == .S,
            //keyEnd[-2] == .t || keyEnd[-2] == .T,
            keyEnd[-1] == .s || keyEnd[-1] == .S {
            upgradeInsecureRequests = HalfHitch(sourceObject: nil,
                                                raw: buffer,
                                                count: bufferSize,
                                                from: valueStart - buffer,
                                                to: ptr - buffer)
        }
        
        if contentLength == nil,
            size >= 14,
            keyEnd[-14] == .c || keyEnd[-14] == .C,
            //keyEnd[-13] == .o || keyEnd[-13] == .O,
            keyEnd[-12] == .n || keyEnd[-12] == .N,
            //keyEnd[-11] == .t || keyEnd[-11] == .T,
            keyEnd[-10] == .e || keyEnd[-10] == .E,
            //keyEnd[-9] == .n || keyEnd[-9] == .N,
            keyEnd[-8] == .t || keyEnd[-8] == .T,
            //keyEnd[-7] == .minus,
            keyEnd[-6] == .l || keyEnd[-6] == .L,
            //keyEnd[-5] == .e || keyEnd[-5] == .E,
            keyEnd[-4] == .n || keyEnd[-4] == .N,
            //keyEnd[-3] == .g || keyEnd[-3] == .G,
            keyEnd[-2] == .t || keyEnd[-2] == .T,
            keyEnd[-1] == .h || keyEnd[-1] == .H {
            contentLength = HalfHitch(sourceObject: nil,
                                      raw: buffer,
                                      count: bufferSize,
                                      from: valueStart - buffer,
                                      to: ptr - buffer)
        }
        
        if contentType == nil,
            size >= 12,
            keyEnd[-12] == .c || keyEnd[-12] == .C,
            //keyEnd[-11] == .o || keyEnd[-11] == .O,
            keyEnd[-10] == .n || keyEnd[-10] == .N,
            //keyEnd[-9] == .t || keyEnd[-9] == .T,
            keyEnd[-8] == .e || keyEnd[-8] == .E,
            //keyEnd[-7] == .n || keyEnd[-7] == .N,
            keyEnd[-6] == .t || keyEnd[-6] == .T,
            //keyEnd[-5] == .minus,
            keyEnd[-4] == .t || keyEnd[-4] == .T,
            //keyEnd[-3] == .y || keyEnd[-3] == .Y,
            keyEnd[-2] == .p || keyEnd[-2] == .P,
            keyEnd[-1] == .e || keyEnd[-1] == .E {
            contentType = HalfHitch(sourceObject: nil,
                                    raw: buffer,
                                    count: bufferSize,
                                    from: valueStart - buffer,
                                    to: ptr - buffer)
        }
        
        if contentDisposition == nil,
            size >= 19,
            keyEnd[-19] == .c || keyEnd[-19] == .C,
            //keyEnd[-18] == .o || keyEnd[-18] == .O,
            keyEnd[-17] == .n || keyEnd[-17] == .N,
            //keyEnd[-16] == .t || keyEnd[-16] == .T,
            keyEnd[-15] == .e || keyEnd[-15] == .E,
            //keyEnd[-14] == .n || keyEnd[-14] == .N,
            keyEnd[-13] == .t || keyEnd[-13] == .T,
            //keyEnd[-12] == .minus,
            keyEnd[-11] == .d || keyEnd[-11] == .D,
            //keyEnd[-10] == .i || keyEnd[-10] == .I,
            keyEnd[-9] == .s || keyEnd[-9] == .S,
            //keyEnd[-8] == .p || keyEnd[-8] == .P,
            keyEnd[-7] == .o || keyEnd[-7] == .O,
            //keyEnd[-6] == .s || keyEnd[-6] == .S,
            keyEnd[-5] == .i || keyEnd[-5] == .I,
            //keyEnd[-4] == .t || keyEnd[-4] == .T,
            keyEnd[-3] == .i || keyEnd[-3] == .I,
            //keyEnd[-2] == .o || keyEnd[-2] == .O,
            keyEnd[-1] == .n || keyEnd[-1] == .N {
            contentDisposition = HalfHitch(sourceObject: nil,
                                           raw: buffer,
                                           count: bufferSize,
                                           from: valueStart - buffer,
                                           to: ptr - buffer)
        }
        
        if ifModifiedSince == nil,
            size >= 17,
            keyEnd[-17] == .i || keyEnd[-17] == .I,
            //keyEnd[-16] == .f || keyEnd[-16] == .F,
            keyEnd[-15] == .minus,
            //keyEnd[-14] == .m || keyEnd[-14] == .M,
            keyEnd[-13] == .o || keyEnd[-13] == .O,
            //keyEnd[-12] == .d || keyEnd[-12] == .D,
            keyEnd[-11] == .i || keyEnd[-11] == .I,
            //keyEnd[-10] == .f || keyEnd[-10] == .F,
            keyEnd[-9] == .i || keyEnd[-9] == .I,
            //keyEnd[-8] == .e || keyEnd[-8] == .E,
            keyEnd[-7] == .d || keyEnd[-7] == .D,
            //keyEnd[-6] == .minus,
            keyEnd[-5] == .s || keyEnd[-5] == .S,
            //keyEnd[-4] == .i || keyEnd[-4] == .I,
            keyEnd[-3] == .n || keyEnd[-3] == .N,
            //keyEnd[-2] == .c || keyEnd[-2] == .C,
            keyEnd[-1] == .e || keyEnd[-1] == .E {
            ifModifiedSince = HalfHitch(sourceObject: nil,
                                        raw: buffer,
                                        count: bufferSize,
                                        from: valueStart - buffer,
                                        to: ptr - buffer)
        }
        
        if ifNoneMatch == nil,
            size >= 13,
            keyEnd[-13] == .i || keyEnd[-13] == .I,
            //keyEnd[-12] == .f || keyEnd[-12] == .F,
            keyEnd[-11] == .minus,
            //keyEnd[-10] == .n || keyEnd[-10] == .N,
            keyEnd[-9] == .o || keyEnd[-9] == .O,
            //keyEnd[-8] == .n || keyEnd[-8] == .N,
            keyEnd[-7] == .e || keyEnd[-7] == .E,
            //keyEnd[-6] == .minus,
            keyEnd[-5] == .m || keyEnd[-5] == .M,
            //keyEnd[-4] == .a || keyEnd[-4] == .A,
            keyEnd[-3] == .t || keyEnd[-3] == .T,
            //keyEnd[-2] == .c || keyEnd[-2] == .C,
            keyEnd[-1] == .h || keyEnd[-1] == .H {
            ifNoneMatch = HalfHitch(sourceObject: nil,
                                    raw: buffer,
                                    count: bufferSize,
                                    from: valueStart - buffer,
                                    to: ptr - buffer)
        }
        
        if cookie == nil,
            size >= 6,
            keyEnd[-6] == .c || keyEnd[-6] == .C,
            //keyEnd[-5] == .o || keyEnd[-5] == .O,
            keyEnd[-4] == .o || keyEnd[-4] == .O,
            //keyEnd[-3] == .k || keyEnd[-3] == .K,
            keyEnd[-2] == .i || keyEnd[-2] == .I,
            keyEnd[-1] == .e || keyEnd[-1] == .E {
            cookie = HalfHitch(sourceObject: nil,
                               raw: buffer,
                               count: bufferSize,
                               from: valueStart - buffer,
                               to: ptr - buffer)
        }
        
        if expect == nil,
            size >= 6,
            keyEnd[-6] == .e || keyEnd[-6] == .E,
            //keyEnd[-5] == .x || keyEnd[-5] == .X,
            keyEnd[-4] == .p || keyEnd[-4] == .P,
            //keyEnd[-3] == .e || keyEnd[-3] == .E,
            keyEnd[-2] == .c || keyEnd[-2] == .C,
            keyEnd[-1] == .t || keyEnd[-1] == .T {
            expect = HalfHitch(sourceObject: nil,
                               raw: buffer,
                               count: bufferSize,
                               from: valueStart - buffer,
                               to: ptr - buffer)
        }
        
        if flynnTag == nil,
            size >= 9,
            keyEnd[-9] == .f || keyEnd[-9] == .F,
            //keyEnd[-8] == .l || keyEnd[-8] == .L,
            keyEnd[-7] == .y || keyEnd[-7] == .Y,
            //keyEnd[-6] == .n || keyEnd[-6] == .N,
            keyEnd[-5] == .n || keyEnd[-5] == .N,
            //keyEnd[-4] == .minus,
            keyEnd[-3] == .t || keyEnd[-3] == .T,
            //keyEnd[-2] == .a || keyEnd[-2] == .A,
            keyEnd[-1] == .g || keyEnd[-1] == .G {
            flynnTag = HalfHitch(sourceObject: nil,
                                 raw: buffer,
                                 count: bufferSize,
                                 from: valueStart - buffer,
                                 to: ptr - buffer)
        }
        
        if sessionId == nil,
            size >= 10,
            keyEnd[-10] == .s || keyEnd[-10] == .S,
            //keyEnd[-9] == .e || keyEnd[-9] == .E,
            keyEnd[-8] == .s || keyEnd[-8] == .S,
            //keyEnd[-7] == .s || keyEnd[-7] == .S,
            keyEnd[-6] == .i || keyEnd[-6] == .I,
            //keyEnd[-5] == .o || keyEnd[-5] == .O,
            keyEnd[-4] == .n || keyEnd[-4] == .N,
            //keyEnd[-3] == .minus,
            keyEnd[-2] == .i || keyEnd[-2] == .I,
            keyEnd[-1] == .d || keyEnd[-1] == .D {
            sessionId = HalfHitch(sourceObject: nil,
                                  raw: buffer,
                                  count: bufferSize,
                                  from: valueStart - buffer,
                                  to: ptr - buffer)
        }
        
        if xForwardedFor == nil,
            size >= 15,
            keyEnd[-15] == .x || keyEnd[-15] == .X,
            //keyEnd[-14] == .minus,
            keyEnd[-13] == .f || keyEnd[-13] == .F,
            //keyEnd[-12] == .o || keyEnd[-12] == .O,
            keyEnd[-11] == .r || keyEnd[-11] == .R,
            //keyEnd[-10] == .w || keyEnd[-10] == .W,
            keyEnd[-9] == .a || keyEnd[-9] == .A,
            //keyEnd[-8] == .r || keyEnd[-8] == .R,
            keyEnd[-7] == .d || keyEnd[-7] == .D,
            //keyEnd[-6] == .e || keyEnd[-6] == .E,
            keyEnd[-5] == .d || keyEnd[-5] == .D,
            //keyEnd[-4] == .minus,
            keyEnd[-3] == .f || keyEnd[-3] == .F,
            //keyEnd[-2] == .o || keyEnd[-2] == .O,
            keyEnd[-1] == .r || keyEnd[-1] == .R {
            xForwardedFor = HalfHitch(sourceObject: nil,
                                      raw: buffer,
                                      count: bufferSize,
                                      from: valueStart - buffer,
                                      to: ptr - buffer)
        }
        
        if deviceId == nil,
            size >= 9,
            keyEnd[-9] == .d || keyEnd[-9] == .D,
            //keyEnd[-8] == .e || keyEnd[-8] == .E,
            keyEnd[-7] == .v || keyEnd[-7] == .V,
            //keyEnd[-6] == .i || keyEnd[-6] == .I,
            keyEnd[-5] == .c || keyEnd[-5] == .C,
            //keyEnd[-4] == .e || keyEnd[-4] == .E,
            keyEnd[-3] == .minus,
            keyEnd[-2] == .i || keyEnd[-2] == .I,
            keyEnd[-1] == .d || keyEnd[-1] == .D {
            deviceId = HalfHitch(sourceObject: nil,
                                 raw: buffer,
                                 count: bufferSize,
                                 from: valueStart - buffer,
                                 to: ptr - buffer)
        }
        
        if waitingCount == nil,
            size >= 13,
            keyEnd[-13] == .w || keyEnd[-13] == .W,
            //keyEnd[-12] == .a || keyEnd[-12] == .A,
            keyEnd[-11] == .i || keyEnd[-11] == .I,
            //keyEnd[-10] == .t || keyEnd[-10] == .T,
            keyEnd[-9] == .i || keyEnd[-9] == .I,
            //keyEnd[-8] == .n || keyEnd[-8] == .N,
            //keyEnd[-7] == .g || keyEnd[-7] == .G,
            keyEnd[-6] == .minus,
            //keyEnd[-5] == .c || keyEnd[-5] == .C,
            keyEnd[-4] == .o || keyEnd[-4] == .O,
            //keyEnd[-3] == .u || keyEnd[-3] == .U,
            keyEnd[-2] == .n || keyEnd[-2] == .N,
            keyEnd[-1] == .t || keyEnd[-1] == .T {
            waitingCount = HalfHitch(sourceObject: nil,
                                     raw: buffer,
                                     count: bufferSize,
                                     from: valueStart - buffer,
                                     to: ptr - buffer)
        }
        
        if activeCount == nil,
            size >= 12,
            keyEnd[-12] == .a || keyEnd[-12] == .A,
            //keyEnd[-11] == .c || keyEnd[-11] == .C,
            keyEnd[-10] == .t || keyEnd[-10] == .T,
            //keyEnd[-9] == .i || keyEnd[-9] == .I,
            keyEnd[-8] == .v || keyEnd[-8] == .V,
            //keyEnd[-7] == .e || keyEnd[-7] == .E,
            keyEnd[-6] == .minus,
            //keyEnd[-5] == .c || keyEnd[-5] == .C,
            keyEnd[-4] == .o || keyEnd[-4] == .O,
            //keyEnd[-3] == .u || keyEnd[-3] == .U,
            keyEnd[-2] == .n || keyEnd[-2] == .N,
            keyEnd[-1] == .t || keyEnd[-1] == .T {
            activeCount = HalfHitch(sourceObject: nil,
                                    raw: buffer,
                                    count: bufferSize,
                                    from: valueStart - buffer,
                                    to: ptr - buffer)
        }
        
        if maxConcurrent == nil,
            size >= 14,
            keyEnd[-14] == .m || keyEnd[-14] == .M,
            //keyEnd[-13] == .a || keyEnd[-13] == .A,
            keyEnd[-12] == .x || keyEnd[-12] == .X,
            //keyEnd[-11] == .minus,
            keyEnd[-10] == .c || keyEnd[-10] == .C,
            //keyEnd[-9] == .o || keyEnd[-9] == .O,
            keyEnd[-8] == .n || keyEnd[-8] == .N,
            //keyEnd[-7] == .c || keyEnd[-7] == .C,
            keyEnd[-6] == .u || keyEnd[-6] == .U,
            //keyEnd[-5] == .r || keyEnd[-5] == .R,
            keyEnd[-4] == .r || keyEnd[-4] == .R,
            //keyEnd[-3] == .e, || keyEnd[-3] == .E
            keyEnd[-2] == .n || keyEnd[-2] == .N,
            keyEnd[-1] == .t || keyEnd[-1] == .T {
            maxConcurrent = HalfHitch(sourceObject: nil,
                                      raw: buffer,
                                      count: bufferSize,
                                      from: valueStart - buffer,
                                      to: ptr - buffer)
        }
    }
}
