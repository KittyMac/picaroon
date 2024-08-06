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
            keyEnd[-10] == .U || keyEnd[-10] == .u,
            //keyEnd[-9] == .s,
            keyEnd[-8] == .e,
            //keyEnd[-7] == .r,
            keyEnd[-6] == .minus,
            //keyEnd[-5] == .A || keyEnd[-5] == .a,
            keyEnd[-4] == .g,
            //keyEnd[-3] == .e,
            keyEnd[-2] == .n,
            keyEnd[-1] == .t {
            userAgent = HalfHitch(sourceObject: nil,
                                  raw: buffer,
                                  count: bufferSize,
                                  from: valueStart - buffer,
                                  to: ptr - buffer)
        }
        
        if authorization == nil,
            size >= 13,
            keyEnd[-13] == .A || keyEnd[-13] == .a,
            //keyEnd[-12] == .u,
            keyEnd[-11] == .t,
            //keyEnd[-10] == .h,
            keyEnd[-9] == .o,
            //keyEnd[-8] == .r,
            keyEnd[-7] == .i,
            //keyEnd[-6] == .z,
            keyEnd[-5] == .a,
            //keyEnd[-4] == .t,
            keyEnd[-3] == .i,
            //keyEnd[-2] == .o,
            keyEnd[-1] == .n {
            authorization = HalfHitch(sourceObject: nil,
                                      raw: buffer,
                                      count: bufferSize,
                                      from: valueStart - buffer,
                                      to: ptr - buffer)
        }
        
        if accept == nil,
            size >= 6,
            keyEnd[-6] == .A || keyEnd[-6] == .a,
            //keyEnd[-5] == .c,
            keyEnd[-4] == .c,
            //keyEnd[-3] == .e,
            keyEnd[-2] == .p,
            keyEnd[-1] == .t {
            accept = HalfHitch(sourceObject: nil,
                               raw: buffer,
                               count: bufferSize,
                               from: valueStart - buffer,
                               to: ptr - buffer)
        }
        
        if acceptEncoding == nil,
            size >= 15,
            keyEnd[-15] == .A || keyEnd[-15] == .a,
            //keyEnd[-14] == .c,
            keyEnd[-13] == .c,
            //keyEnd[-12] == .e,
            keyEnd[-11] == .p,
            //keyEnd[-10] == .t,
            keyEnd[-9] == .minus,
            //keyEnd[-8] == .E || keyEnd[-8] == .e,
            keyEnd[-7] == .n,
            //keyEnd[-6] == .c,
            keyEnd[-5] == .o,
            //keyEnd[-4] == .d,
            keyEnd[-3] == .i,
            //keyEnd[-2] == .n,
            keyEnd[-1] == .g {
            acceptEncoding = HalfHitch(sourceObject: nil,
                                       raw: buffer,
                                       count: bufferSize,
                                       from: valueStart - buffer,
                                       to: ptr - buffer)
        }
        
        if acceptCharset == nil,
            size >= 14,
            keyEnd[-14] == .A || keyEnd[-14] == .a,
            //keyEnd[-13] == .c,
            keyEnd[-12] == .c,
            //keyEnd[-11] == .e,
            keyEnd[-10] == .p,
            //keyEnd[-9] == .t,
            keyEnd[-8] == .minus,
            //keyEnd[-7] == .C || keyEnd[-7] == .c,
            keyEnd[-6] == .h,
            //keyEnd[-5] == .a,
            keyEnd[-4] == .r,
            //keyEnd[-3] == .s,
            keyEnd[-2] == .e,
            keyEnd[-1] == .t {
            acceptCharset = HalfHitch(sourceObject: nil,
                                      raw: buffer,
                                      count: bufferSize,
                                      from: valueStart - buffer,
                                      to: ptr - buffer)
        }
        
        if acceptLanguage == nil,
            size >= 15,
            keyEnd[-15] == .A || keyEnd[-15] == .a,
            //keyEnd[-14] == .c,
            keyEnd[-13] == .c,
            //keyEnd[-12] == .e,
            keyEnd[-11] == .p,
            //keyEnd[-10] == .t,
            keyEnd[-9] == .minus,
            //keyEnd[-8] == .L || keyEnd[-8] == .l,
            keyEnd[-7] == .a,
            //keyEnd[-6] == .n,
            keyEnd[-5] == .g,
            //keyEnd[-4] == .u,
            keyEnd[-3] == .a,
            //keyEnd[-2] == .g,
            keyEnd[-1] == .e {
            acceptLanguage = HalfHitch(sourceObject: nil,
                                       raw: buffer,
                                       count: bufferSize,
                                       from: valueStart - buffer,
                                       to: ptr - buffer)
        }
        
        if connection == nil,
            size >= 10,
            keyEnd[-10] == .C || keyEnd[-10] == .c,
            //keyEnd[-9] == .o,
            keyEnd[-8] == .n,
            //keyEnd[-7] == .n,
            keyEnd[-6] == .e,
            //keyEnd[-5] == .c,
            keyEnd[-4] == .t,
            //keyEnd[-3] == .i,
            keyEnd[-2] == .o,
            keyEnd[-1] == .n {
            connection = HalfHitch(sourceObject: nil,
                                   raw: buffer,
                                   count: bufferSize,
                                   from: valueStart - buffer,
                                   to: ptr - buffer)
        }
        
        if upgradeInsecureRequests == nil,
            size >= 25,
            keyEnd[-25] == .U || keyEnd[-25] == .u,
            //keyEnd[-24] == .p,
            keyEnd[-23] == .g,
            //keyEnd[-22] == .r,
            keyEnd[-21] == .a,
            //keyEnd[-20] == .d,
            keyEnd[-19] == .e,
            //keyEnd[-18] == .minus,
            keyEnd[-17] == .I || keyEnd[-17] == .i,
            //keyEnd[-16] == .n,
            keyEnd[-15] == .s,
            //keyEnd[-14] == .e,
            keyEnd[-13] == .c,
            //keyEnd[-12] == .u,
            keyEnd[-11] == .r,
            //keyEnd[-10] == .e,
            keyEnd[-9] == .minus,
            //keyEnd[-8] == .R || keyEnd[-8] == .r,
            keyEnd[-7] == .e,
            //keyEnd[-6] == .q,
            keyEnd[-5] == .u,
            //keyEnd[-4] == .e,
            keyEnd[-3] == .s,
            //keyEnd[-2] == .t,
            keyEnd[-1] == .s {
            upgradeInsecureRequests = HalfHitch(sourceObject: nil,
                                                raw: buffer,
                                                count: bufferSize,
                                                from: valueStart - buffer,
                                                to: ptr - buffer)
        }
        
        if contentLength == nil,
            size >= 14,
            keyEnd[-14] == .C || keyEnd[-14] == .c,
            //keyEnd[-13] == .o,
            keyEnd[-12] == .n,
            //keyEnd[-11] == .t,
            keyEnd[-10] == .e,
            //keyEnd[-9] == .n,
            keyEnd[-8] == .t,
            //keyEnd[-7] == .minus,
            keyEnd[-6] == .L || keyEnd[-6] == .l,
            //keyEnd[-5] == .e,
            keyEnd[-4] == .n,
            //keyEnd[-3] == .g,
            keyEnd[-2] == .t,
            keyEnd[-1] == .h {
            contentLength = HalfHitch(sourceObject: nil,
                                      raw: buffer,
                                      count: bufferSize,
                                      from: valueStart - buffer,
                                      to: ptr - buffer)
        }
        
        if contentType == nil,
            size >= 12,
            keyEnd[-12] == .C || keyEnd[-12] == .c,
            //keyEnd[-11] == .o,
            keyEnd[-10] == .n,
            //keyEnd[-9] == .t,
            keyEnd[-8] == .e,
            //keyEnd[-7] == .n,
            keyEnd[-6] == .t,
            //keyEnd[-5] == .minus,
            keyEnd[-4] == .T || keyEnd[-4] == .t,
            //keyEnd[-3] == .y,
            keyEnd[-2] == .p,
            keyEnd[-1] == .e {
            contentType = HalfHitch(sourceObject: nil,
                                    raw: buffer,
                                    count: bufferSize,
                                    from: valueStart - buffer,
                                    to: ptr - buffer)
        }
        
        if contentDisposition == nil,
            size >= 19,
            keyEnd[-19] == .C || keyEnd[-19] == .c,
            //keyEnd[-18] == .o,
            keyEnd[-17] == .n,
            //keyEnd[-16] == .t,
            keyEnd[-15] == .e,
            //keyEnd[-14] == .n,
            keyEnd[-13] == .t,
            //keyEnd[-12] == .minus,
            keyEnd[-11] == .D || keyEnd[-11] == .d,
            //keyEnd[-10] == .i,
            keyEnd[-9] == .s,
            //keyEnd[-8] == .p,
            keyEnd[-7] == .o,
            //keyEnd[-6] == .s,
            keyEnd[-5] == .i,
            //keyEnd[-4] == .t,
            keyEnd[-3] == .i,
            //keyEnd[-2] == .o,
            keyEnd[-1] == .n {
            contentDisposition = HalfHitch(sourceObject: nil,
                                           raw: buffer,
                                           count: bufferSize,
                                           from: valueStart - buffer,
                                           to: ptr - buffer)
        }
        
        if ifModifiedSince == nil,
            size >= 17,
            keyEnd[-17] == .I || keyEnd[-17] == .i,
            //keyEnd[-16] == .f,
            keyEnd[-15] == .minus,
            //keyEnd[-14] == .M || keyEnd[-14] == .m,
            keyEnd[-13] == .o,
            //keyEnd[-12] == .d,
            keyEnd[-11] == .i,
            //keyEnd[-10] == .f,
            keyEnd[-9] == .i,
            //keyEnd[-8] == .e,
            keyEnd[-7] == .d,
            //keyEnd[-6] == .minus,
            keyEnd[-5] == .S || keyEnd[-5] == .s,
            //keyEnd[-4] == .i,
            keyEnd[-3] == .n,
            //keyEnd[-2] == .c,
            keyEnd[-1] == .e {
            ifModifiedSince = HalfHitch(sourceObject: nil,
                                        raw: buffer,
                                        count: bufferSize,
                                        from: valueStart - buffer,
                                        to: ptr - buffer)
        }
        
        if ifNoneMatch == nil,
            size >= 13,
            keyEnd[-13] == .I || keyEnd[-13] == .i,
            //keyEnd[-12] == .f,
            keyEnd[-11] == .minus,
            //keyEnd[-10] == .N || keyEnd[-10] == .n,
            keyEnd[-9] == .o,
            //keyEnd[-8] == .n,
            keyEnd[-7] == .e,
            //keyEnd[-6] == .minus,
            keyEnd[-5] == .M || keyEnd[-5] == .m,
            //keyEnd[-4] == .a,
            keyEnd[-3] == .t,
            //keyEnd[-2] == .c,
            keyEnd[-1] == .h {
            ifNoneMatch = HalfHitch(sourceObject: nil,
                                    raw: buffer,
                                    count: bufferSize,
                                    from: valueStart - buffer,
                                    to: ptr - buffer)
        }
        
        if cookie == nil,
            size >= 6,
            keyEnd[-6] == .C || keyEnd[-6] == .c,
            //keyEnd[-5] == .o,
            keyEnd[-4] == .o,
            //keyEnd[-3] == .k,
            keyEnd[-2] == .i,
            keyEnd[-1] == .e {
            cookie = HalfHitch(sourceObject: nil,
                               raw: buffer,
                               count: bufferSize,
                               from: valueStart - buffer,
                               to: ptr - buffer)
        }
        
        if expect == nil,
            size >= 6,
            keyEnd[-6] == .E || keyEnd[-6] == .e,
            //keyEnd[-5] == .x,
            keyEnd[-4] == .p,
            //keyEnd[-3] == .e,
            keyEnd[-2] == .c,
            keyEnd[-1] == .t {
            expect = HalfHitch(sourceObject: nil,
                               raw: buffer,
                               count: bufferSize,
                               from: valueStart - buffer,
                               to: ptr - buffer)
        }
        
        if flynnTag == nil,
            size >= 9,
            keyEnd[-9] == .F || keyEnd[-9] == .f,
            //keyEnd[-8] == .l,
            keyEnd[-7] == .y,
            //keyEnd[-6] == .n,
            keyEnd[-5] == .n,
            //keyEnd[-4] == .minus,
            keyEnd[-3] == .T || keyEnd[-3] == .t,
            //keyEnd[-2] == .a,
            keyEnd[-1] == .g {
            flynnTag = HalfHitch(sourceObject: nil,
                                 raw: buffer,
                                 count: bufferSize,
                                 from: valueStart - buffer,
                                 to: ptr - buffer)
        }
        
        if sessionId == nil,
            size >= 10,
            keyEnd[-10] == .S || keyEnd[-10] == .s,
            //keyEnd[-9] == .e,
            keyEnd[-8] == .s,
            //keyEnd[-7] == .s,
            keyEnd[-6] == .i,
            //keyEnd[-5] == .o,
            keyEnd[-4] == .n,
            //keyEnd[-3] == .minus,
            keyEnd[-2] == .I || keyEnd[-2] == .i,
            keyEnd[-1] == .d {
            sessionId = HalfHitch(sourceObject: nil,
                                  raw: buffer,
                                  count: bufferSize,
                                  from: valueStart - buffer,
                                  to: ptr - buffer)
        }
        
        if xForwardedFor == nil,
            size >= 15,
            keyEnd[-15] == .X || keyEnd[-15] == .x,
            //keyEnd[-14] == .minus,
            keyEnd[-13] == .F || keyEnd[-13] == .f,
            //keyEnd[-12] == .o,
            keyEnd[-11] == .r,
            //keyEnd[-10] == .w,
            keyEnd[-9] == .a,
            //keyEnd[-8] == .r,
            keyEnd[-7] == .d,
            //keyEnd[-6] == .e,
            keyEnd[-5] == .d,
            //keyEnd[-4] == .minus,
            keyEnd[-3] == .F || keyEnd[-3] == .f,
            //keyEnd[-2] == .o,
            keyEnd[-1] == .r {
            xForwardedFor = HalfHitch(sourceObject: nil,
                                      raw: buffer,
                                      count: bufferSize,
                                      from: valueStart - buffer,
                                      to: ptr - buffer)
        }
        
        if deviceId == nil,
            size >= 9,
            keyEnd[-9] == .D || keyEnd[-9] == .d,
            //keyEnd[-8] == .e,
            keyEnd[-7] == .v,
            //keyEnd[-6] == .i,
            keyEnd[-5] == .c,
            //keyEnd[-4] == .e,
            keyEnd[-3] == .minus,
            keyEnd[-2] == .I || keyEnd[-2] == .i,
            keyEnd[-1] == .d {
            deviceId = HalfHitch(sourceObject: nil,
                                 raw: buffer,
                                 count: bufferSize,
                                 from: valueStart - buffer,
                                 to: ptr - buffer)
        }
        
        if waitingCount == nil,
            size >= 13,
            keyEnd[-13] == .W || keyEnd[-13] == .w,
            //keyEnd[-12] == .a,
            keyEnd[-11] == .i,
            //keyEnd[-10] == .t,
            keyEnd[-9] == .i,
            //keyEnd[-8] == .n,
            //keyEnd[-7] == .g,
            keyEnd[-6] == .minus,
            //keyEnd[-5] == .C || keyEnd[-5] == .c,
            keyEnd[-4] == .o,
            //keyEnd[-3] == .u,
            keyEnd[-2] == .n,
            keyEnd[-1] == .t {
            waitingCount = HalfHitch(sourceObject: nil,
                                     raw: buffer,
                                     count: bufferSize,
                                     from: valueStart - buffer,
                                     to: ptr - buffer)
        }
        
        if activeCount == nil,
            size >= 12,
            keyEnd[-12] == .A || keyEnd[-12] == .a,
            //keyEnd[-11] == .c,
            keyEnd[-10] == .t,
            //keyEnd[-9] == .i,
            keyEnd[-8] == .v,
            //keyEnd[-7] == .e,
            keyEnd[-6] == .minus,
            //keyEnd[-5] == .C || keyEnd[-5] == .c,
            keyEnd[-4] == .o,
            //keyEnd[-3] == .u,
            keyEnd[-2] == .n,
            keyEnd[-1] == .t {
            activeCount = HalfHitch(sourceObject: nil,
                                    raw: buffer,
                                    count: bufferSize,
                                    from: valueStart - buffer,
                                    to: ptr - buffer)
        }
        
        if maxConcurrent == nil,
            size >= 14,
            keyEnd[-14] == .M || keyEnd[-14] == .m,
            //keyEnd[-13] == .a,
            keyEnd[-12] == .x,
            //keyEnd[-11] == .minus,
            keyEnd[-10] == .C || keyEnd[-10] == .c,
            //keyEnd[-9] == .o,
            keyEnd[-8] == .n,
            //keyEnd[-7] == .c,
            keyEnd[-6] == .u,
            //keyEnd[-5] == .r,
            keyEnd[-4] == .r,
            //keyEnd[-3] == .e,
            keyEnd[-2] == .n,
            keyEnd[-1] == .t {
            maxConcurrent = HalfHitch(sourceObject: nil,
                                      raw: buffer,
                                      count: bufferSize,
                                      from: valueStart - buffer,
                                      to: ptr - buffer)
        }
    }
}
